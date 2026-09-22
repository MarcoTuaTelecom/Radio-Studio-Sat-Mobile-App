import SwiftUI
import AVFoundation
import MediaPlayer
import Foundation

struct Station: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let tagline: String
    let streamURL: URL

    enum CodingKeys: String, CodingKey {
        case id, name, tagline
        case streamURL = "stream_url"
    }
}

let fallbackStations: [Station] = [
    Station(id: "radioprincipal", name: "Rádio Principal", tagline: "Programação Studio Sat", streamURL: URL(string: "https://radio.studiosatweb.com.br/radioprincipal/index.m3u8")!),
    Station(id: "radiopop", name: "Rádio Pop", tagline: "Pop nacional e internacional", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiopop/index.m3u8")!),
    Station(id: "radiorock", name: "Rádio Rock", tagline: "Rock clássico e contemporâneo", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiorock/index.m3u8")!),
    Station(id: "radioclassicas", name: "Rádio Clássicas", tagline: "Clássicos que atravessam gerações", streamURL: URL(string: "https://radio.studiosatweb.com.br/radioclassicas/index.m3u8")!),
    Station(id: "radiocountry", name: "Rádio Country", tagline: "Country americano", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiocountry/index.m3u8")!)
]

/// Player nativo da Rádio Sat.
///
/// O HLS é entregue diretamente ao AVPlayer. Não há AVAudioEngine,
/// tap de áudio, equalizador, analisador ou mudança automática de rate.
@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var selected: Station = fallbackStations[0]
    @Published private(set) var isPlaying = false

    private let player = AVPlayer()

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    func play(_ station: Station? = nil) {
        if let station {
            selected = station
            let item = AVPlayerItem(url: station.streamURL)
            player.replaceCurrentItem(with: item)
        } else if player.currentItem == nil {
            player.replaceCurrentItem(with: AVPlayerItem(url: selected.streamURL))
        }

        // AVPlayer usa 1.0 como velocidade normal. Não fazemos chase de live edge.
        player.defaultRate = 1.0
        player.playImmediately(atRate: 1.0)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession:", error)
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        // Rádio ao vivo não expõe seek.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: selected.name,
            MPMediaItemPropertyArtist: "Studio Sat",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
    }
}

struct ContentView: View {
    @EnvironmentObject private var player: RadioPlayer
    @State private var stations = fallbackStations

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.03, green: 0.04, blue: 0.07).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("STUDIO SAT WEB")
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)

                        Text("Rádio Sat V2")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(player.selected.name)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            Text(player.selected.tagline)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            player.toggle()
                        } label: {
                            Label(
                                player.isPlaying ? "Pausar" : "Ouvir ao vivo",
                                systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Emissoras")
                            .font(.headline)
                            .foregroundStyle(.white)

                        ForEach(stations) { station in
                            Button {
                                player.play(station)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(station.name).font(.headline)
                                    Text(station.tagline).font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@main
struct StudioSatApp: App {
    @StateObject private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
        }
    }
}
