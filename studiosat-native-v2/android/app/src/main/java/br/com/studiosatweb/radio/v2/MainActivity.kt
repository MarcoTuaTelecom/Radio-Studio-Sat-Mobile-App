package br.com.studiosatweb.radio.v2

import android.content.ComponentName
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

/**
 * Modelo simples da emissora.
 *
 * O player recebe somente [streamUrl]. Nenhum metadado visual intercepta os
 * samples de áudio.
 */
data class Station(
    val id: String,
    val name: String,
    val tagline: String,
    val streamUrl: String
)

val studioSatStations = listOf(
    Station("radioprincipal", "Rádio Principal", "Programação Studio Sat", "https://radio.studiosatweb.com.br/radioprincipal/index.m3u8"),
    Station("radiopop", "Rádio Pop", "Pop nacional e internacional", "https://radio.studiosatweb.com.br/radiopop/index.m3u8"),
    Station("radiorock", "Rádio Rock", "Rock clássico e contemporâneo", "https://radio.studiosatweb.com.br/radiorock/index.m3u8"),
    Station("radioclassicas", "Rádio Clássicas", "Clássicos que atravessam gerações", "https://radio.studiosatweb.com.br/radioclassicas/index.m3u8"),
    Station("radiocountry", "Rádio Country", "Country americano", "https://radio.studiosatweb.com.br/radiocountry/index.m3u8")
)

/**
 * Serviço nativo de reprodução.
 *
 * A cadeia é HLS -> Media3/ExoPlayer -> MediaCodec/AudioTrack.
 * Não existe AudioEffect, equalizador, analisador, sampling ou time-stretch
 * definido pela aplicação. A velocidade é fixada em 1.0.
 */
class PlaybackService : MediaSessionService() {
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val player = ExoPlayer.Builder(this)
            .build()
            .apply {
                setAudioAttributes(audioAttributes, true)
                playbackParameters = PlaybackParameters(1.0f)
                repeatMode = Player.REPEAT_MODE_OFF
            }

        mediaSession = MediaSession.Builder(this, player).build()
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo
    ): MediaSession? = mediaSession

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var controllerFuture: ListenableFuture<MediaController>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val token = SessionToken(
            this,
            ComponentName(this, PlaybackService::class.java)
        )
        controllerFuture = MediaController.Builder(this, token).buildAsync()

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                StudioSatScreen(controllerFuture)
            }
        }
    }

    override fun onDestroy() {
        MediaController.releaseFuture(controllerFuture)
        super.onDestroy()
    }
}

@Composable
private fun StudioSatScreen(controllerFuture: ListenableFuture<MediaController>) {
    var controller by remember { mutableStateOf<MediaController?>(null) }
    var selected by remember { mutableStateOf(studioSatStations.first()) }
    var playing by remember { mutableStateOf(false) }

    DisposableEffect(controllerFuture) {
        controllerFuture.addListener(
            { controller = runCatching { controllerFuture.get() }.getOrNull() },
            { command -> command.run() }
        )
        onDispose { }
    }

    fun playStation(station: Station) {
        val player = controller ?: return

        val mediaItem = MediaItem.Builder()
            .setUri(station.streamUrl)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(station.name)
                    .setArtist("Studio Sat")
                    .setIsBrowsable(false)
                    .setIsPlayable(true)
                    .build()
            )
            .build()

        // Não reaproveitamos buffer de outra estação e não fazemos seek.
        player.stop()
        player.clearMediaItems()
        player.playbackParameters = PlaybackParameters(1.0f)
        player.setMediaItem(mediaItem)
        player.prepare()
        player.play()
        selected = station
        playing = true
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = Color(0xFF080B12)
    ) {
        Column(
            modifier = Modifier.padding(22.dp)
        ) {
            Text("STUDIO SAT WEB", color = Color(0xFF38BDF8))
            Text("Rádio Sat V2", style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(8.dp))
            Text(selected.name, style = MaterialTheme.typography.titleLarge)
            Text(selected.tagline, color = Color(0xFF94A3B8))

            Spacer(Modifier.height(22.dp))

            Button(
                onClick = {
                    val player = controller ?: return@Button
                    if (playing) {
                        player.pause()
                        playing = false
                    } else {
                        if (player.mediaItemCount == 0) {
                            playStation(selected)
                        } else {
                            player.playbackParameters = PlaybackParameters(1.0f)
                            player.play()
                            playing = true
                        }
                    }
                }
            ) {
                Text(if (playing) "Pausar" else "Ouvir ao vivo")
            }

            Spacer(Modifier.height(28.dp))
            Text("Emissoras", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(10.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(studioSatStations) { station ->
                    OutlinedButton(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = { playStation(station) }
                    ) {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.Start
                        ) {
                            Text(station.name)
                            Text(station.tagline, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}
