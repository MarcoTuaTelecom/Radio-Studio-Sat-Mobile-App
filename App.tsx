import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StatusBar as RNStatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import {
  requestRecordingPermissionsAsync,
  setAudioModeAsync,
  useAudioPlayer,
  useAudioPlayerStatus,
  useAudioSampleListener,
} from 'expo-audio';
import { LinearGradient } from 'expo-linear-gradient';
import { DEFAULT_STATION, STATIONS } from './src/config/stations';
import { fetchCarousel, fetchNowPlaying } from './src/services/api';
import { CarouselItem, NowPlaying, Station } from './src/types';
import { VuMeter } from './src/components/VuMeter';
import { MediaCarousel } from './src/components/MediaCarousel';
import { StationSelector } from './src/components/StationSelector';

const emptyNow: NowPlaying = { program: 'Ao vivo', artist: 'Radio Studio Sat', track: 'Programação ao vivo' };

function rms(sample: { channels: Array<{ frames: number[] }> }): number {
  let sum = 0;
  let count = 0;
  for (const channel of sample.channels) {
    for (const value of channel.frames) {
      sum += value * value;
      count += 1;
    }
  }
  if (!count) return 0;
  const raw = Math.sqrt(sum / count);
  return Math.min(1, Math.pow(raw * 3.4, 0.72));
}

type AudioPlayerHandle = ReturnType<typeof useAudioPlayer>;

function AudioSampler({ player, onLevel }: { player: AudioPlayerHandle; onLevel: (level: number) => void }) {
  useAudioSampleListener(player, (sample) => onLevel(rms(sample)));
  return null;
}

export default function App() {
  const [station, setStation] = useState<Station>(DEFAULT_STATION);
  const [now, setNow] = useState<NowPlaying>(emptyNow);
  const [carousel, setCarousel] = useState<CarouselItem[]>([]);
  const [metadataOnline, setMetadataOnline] = useState(false);
  const [vuLevel, setVuLevel] = useState(0);
  const [samplingAllowed, setSamplingAllowed] = useState(Platform.OS !== 'android');
  const wasPlaying = useRef(false);

  const player = useAudioPlayer(station.streamUrl, {
    updateInterval: 500,
    preferredForwardBufferDuration: 12,
  });
  const status = useAudioPlayerStatus(player);

  useEffect(() => {
    setAudioModeAsync({
      playsInSilentMode: true,
      shouldPlayInBackground: true,
      interruptionMode: 'doNotMix',
    }).catch(() => undefined);
  }, []);

  const refreshMetadata = useCallback(async () => {
    try {
      const data = await fetchNowPlaying(station);
      setNow({ ...emptyNow, ...data });
      setMetadataOnline(true);
    } catch {
      setMetadataOnline(false);
      setNow((current) => ({ ...emptyNow, ...current, station: station.name }));
    }
  }, [station]);

  const refreshCarousel = useCallback(async () => {
    try {
      setCarousel(await fetchCarousel(station.id));
    } catch {
      setCarousel([]);
    }
  }, [station.id]);

  useEffect(() => {
    refreshMetadata();
    refreshCarousel();
    const metadataTimer = setInterval(refreshMetadata, 8000);
    const carouselTimer = setInterval(refreshCarousel, 60000);
    return () => {
      clearInterval(metadataTimer);
      clearInterval(carouselTimer);
    };
  }, [refreshMetadata, refreshCarousel]);

  useEffect(() => {
    const title = now.track || 'Programação ao vivo';
    const artist = now.artist || station.name;
    const metadata = { title, artist, albumTitle: station.name, artworkUrl: now.cover };
    if (status.playing) {
      player.setActiveForLockScreen(true, metadata, {
        isLiveStream: true,
        showSeekBackward: false,
        showSeekForward: false,
      });
    }
    try {
      player.updateLockScreenMetadata(metadata);
    } catch {
      // lock-screen metadata is best effort until playback becomes active
    }
  }, [now.artist, now.cover, now.track, player, station.name, status.playing]);

  const chooseStation = useCallback(
    async (next: Station) => {
      if (next.id === station.id) return;
      wasPlaying.current = status.playing;
      player.pause();
      setStation(next);
      setNow({ ...emptyNow, station: next.name });
      setCarousel([]);
      setVuLevel(0);
      player.replace(next.streamUrl);
      if (wasPlaying.current) {
        setTimeout(() => player.play(), 120);
      }
    },
    [player, station.id, status.playing],
  );

  const ensureSamplingPermission = useCallback(async (): Promise<boolean> => {
    if (Platform.OS !== 'android' || samplingAllowed) return true;
    return await new Promise<boolean>((resolve) => {
      Alert.alert(
        'VU em tempo real',
        'O Android exige permissão de áudio para liberar as amostras do som que o próprio app está reproduzindo. A Studio Sat não grava nem envia o seu microfone.',
        [
          { text: 'Agora não', style: 'cancel', onPress: () => resolve(false) },
          {
            text: 'Ativar VU',
            onPress: async () => {
              try {
                const { granted } = await requestRecordingPermissionsAsync();
                setSamplingAllowed(granted);
                resolve(granted);
              } catch {
                resolve(false);
              }
            },
          },
        ],
        { cancelable: false },
      );
    });
  }, [samplingAllowed]);

  const togglePlayback = useCallback(async () => {
    if (status.playing) {
      player.pause();
      setVuLevel(0);
      return;
    }
    await ensureSamplingPermission();
    player.setActiveForLockScreen(
      true,
      {
        title: now.track || 'Programação ao vivo',
        artist: now.artist || station.name,
        albumTitle: station.name,
        artworkUrl: now.cover,
      },
      { isLiveStream: true, showSeekBackward: false, showSeekForward: false },
    );
    player.play();
  }, [ensureSamplingPermission, now.artist, now.cover, now.track, player, station.name, status.playing]);

  const translation = now.translationPtBr || now.translation;
  const liveLabel = status.isBuffering ? 'CONECTANDO' : status.playing ? 'AO VIVO' : 'PAUSADO';
  const cover = useMemo(() => now.cover, [now.cover]);

  return (
    <SafeAreaView style={styles.safe}>
      {samplingAllowed && (
        <AudioSampler
          player={player}
          onLevel={(next) => setVuLevel((previous) => previous * 0.45 + next * 0.55)}
        />
      )}
      <StatusBar style="dark" />
      <View style={styles.app}>
        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.header}>
            <View>
              <Text style={styles.brand}>STUDIO SAT</Text>
              <Text style={styles.brandSub}>cinco rádios em um aplicativo</Text>
            </View>
            <View style={[styles.livePill, { backgroundColor: station.softAccent }]}>
              <View style={[styles.liveDot, { backgroundColor: station.accent }]} />
              <Text style={[styles.liveText, { color: station.accent }]}>{liveLabel}</Text>
            </View>
          </View>

          <LinearGradient colors={['#FFFFFF', station.softAccent]} style={styles.hero}>
            <View style={styles.heroTop}>
              <View style={styles.stationCopy}>
                <Text style={styles.stationName}>{station.name}</Text>
                <Text style={styles.stationDescription}>{station.description}</Text>
              </View>
              <View style={[styles.cover, { backgroundColor: station.softAccent }]}>
                {cover ? (
                  <Image source={{ uri: cover }} style={styles.coverImage} resizeMode="cover" />
                ) : (
                  <Text style={[styles.coverFallback, { color: station.accent }]}>SS</Text>
                )}
              </View>
            </View>

            <View style={styles.nowBlock}>
              <Text style={styles.artist} numberOfLines={1}>{now.artist || 'Radio Studio Sat'}</Text>
              <Text style={styles.track} numberOfLines={2}>{now.track || 'Programação ao vivo'}</Text>
              <View style={styles.metaRow}>
                {!!now.program && <Text style={styles.program}>{now.program}</Text>}
                {!!now.presenter && <Text style={styles.presenter}>• {now.presenter}</Text>}
                <Text style={[styles.sourceState, { color: metadataOnline ? '#188657' : '#8A93A3' }]}>• {metadataOnline ? 'metadata ao vivo' : 'aguardando metadata'}</Text>
              </View>
            </View>

            <View style={styles.vuHeader}>
              <Text style={styles.vuLabel}>VU EM TEMPO REAL</Text>
              {!samplingAllowed && <Text style={styles.vuHint}>autorize áudio para visualizar</Text>}
            </View>
            <VuMeter level={status.playing && samplingAllowed ? vuLevel : 0} accent={station.accent} />

            <View style={styles.controls}>
              <Pressable style={styles.secondaryButton} accessibilityLabel="Favoritar">
                <Text style={styles.secondaryIcon}>♡</Text>
              </Pressable>
              <Pressable
                style={[styles.playButton, { backgroundColor: station.accent }]}
                onPress={togglePlayback}
                accessibilityRole="button"
                accessibilityLabel={status.playing ? 'Pausar rádio' : 'Ouvir rádio'}
              >
                {status.isBuffering ? <ActivityIndicator color="#FFFFFF" /> : <Text style={styles.playIcon}>{status.playing ? 'Ⅱ' : '▶'}</Text>}
              </Pressable>
              <View style={styles.secondaryButton}>
                <Text style={styles.secondaryIcon}>◖))</Text>
              </View>
            </View>
          </LinearGradient>

          <View style={styles.translationCard}>
            <View style={styles.translationHead}>
              <Text style={styles.translationLabel}>TRADUÇÃO / CONTEXTO</Text>
              <View style={[styles.translationTag, { backgroundColor: station.softAccent }]}><Text style={{ color: station.accent, fontWeight: '800', fontSize: 10 }}>PT-BR</Text></View>
            </View>
            <Text style={translation ? styles.translationText : styles.translationEmpty}>
              {translation || 'A tradução editorial da música atual aparecerá aqui quando fornecida pelo metadata da emissora.'}
            </Text>
          </View>

          <View style={styles.sectionTitleRow}>
            <Text style={styles.sectionTitle}>Studio Sat agora</Text>
            <Text style={styles.sectionKicker}>vídeo • notícia • comercial</Text>
          </View>
          <MediaCarousel items={carousel} accent={station.accent} />
        </ScrollView>

        <StationSelector stations={STATIONS} selected={station.id} onSelect={chooseStation} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F6F8FC', paddingTop: Platform.OS === 'android' ? RNStatusBar.currentHeight ?? 0 : 0 },
  app: { flex: 1, backgroundColor: '#F6F8FC' },
  content: { padding: 16, paddingBottom: 18, gap: 14 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 3, paddingTop: 4 },
  brand: { fontSize: 18, fontWeight: '900', color: '#141A28', letterSpacing: 0.7 },
  brandSub: { fontSize: 11, color: '#7A8494', marginTop: 2 },
  livePill: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 10, paddingVertical: 7, borderRadius: 99 },
  liveDot: { width: 7, height: 7, borderRadius: 99 },
  liveText: { fontSize: 10, fontWeight: '900', letterSpacing: 0.7 },
  hero: { borderRadius: 30, padding: 18, borderWidth: 1, borderColor: '#E5E9F1' },
  heroTop: { flexDirection: 'row', alignItems: 'flex-start', gap: 14 },
  stationCopy: { flex: 1, paddingTop: 3 },
  stationName: { color: '#161C2A', fontSize: 28, lineHeight: 31, fontWeight: '900', letterSpacing: -0.9 },
  stationDescription: { color: '#727C8C', fontSize: 12, lineHeight: 17, marginTop: 7 },
  cover: { width: 86, height: 86, borderRadius: 24, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  coverImage: { width: '100%', height: '100%' },
  coverFallback: { fontSize: 30, fontWeight: '900', letterSpacing: -2 },
  nowBlock: { marginTop: 24 },
  artist: { color: '#4E5868', fontSize: 15, fontWeight: '700' },
  track: { color: '#111827', fontSize: 30, lineHeight: 33, fontWeight: '900', marginTop: 3, letterSpacing: -0.8 },
  metaRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', marginTop: 9 },
  program: { color: '#6D7686', fontSize: 11, fontWeight: '700' },
  presenter: { color: '#6D7686', fontSize: 11, marginLeft: 4 },
  sourceState: { fontSize: 10, marginLeft: 4, fontWeight: '700' },
  vuHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 22, marginBottom: 3 },
  vuLabel: { color: '#6B7484', fontSize: 9, letterSpacing: 1.4, fontWeight: '900' },
  vuHint: { color: '#9AA2B0', fontSize: 9 },
  controls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 26, marginTop: 13 },
  secondaryButton: { width: 42, height: 42, borderRadius: 99, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E1E6EF', alignItems: 'center', justifyContent: 'center' },
  secondaryIcon: { color: '#4F5868', fontSize: 21, fontWeight: '600' },
  playButton: { width: 62, height: 62, borderRadius: 99, alignItems: 'center', justifyContent: 'center', shadowColor: '#111827', shadowOpacity: 0.12, shadowRadius: 16, shadowOffset: { width: 0, height: 8 }, elevation: 4 },
  playIcon: { color: '#FFFFFF', fontSize: 22, fontWeight: '900', marginLeft: 2 },
  translationCard: { backgroundColor: '#FFFFFF', borderRadius: 22, borderWidth: 1, borderColor: '#E5E9F1', padding: 16 },
  translationHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  translationLabel: { color: '#5E6878', fontSize: 10, letterSpacing: 1.1, fontWeight: '900' },
  translationTag: { paddingHorizontal: 8, paddingVertical: 4, borderRadius: 99 },
  translationText: { color: '#2D3543', fontSize: 14, lineHeight: 20, marginTop: 10 },
  translationEmpty: { color: '#8A93A2', fontSize: 13, lineHeight: 19, marginTop: 10, fontStyle: 'italic' },
  sectionTitleRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 3, paddingHorizontal: 2 },
  sectionTitle: { color: '#171E2B', fontSize: 17, fontWeight: '900' },
  sectionKicker: { color: '#8992A1', fontSize: 10, fontWeight: '700' },
});
