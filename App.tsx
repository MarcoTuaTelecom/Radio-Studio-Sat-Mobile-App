import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Linking,
  Modal,
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
import { CarouselItem, NowPlaying, Station, StationId } from './src/types';
import { VuMeter } from './src/components/VuMeter';
import { MediaCarousel } from './src/components/MediaCarousel';

const emptyNow: NowPlaying = {
  program: 'Ao vivo',
  artist: 'Radio Studio Sat',
  track: 'Programação ao vivo',
};

type Sheet = 'stations' | 'favorites' | 'more' | null;
type AudioPlayerHandle = ReturnType<typeof useAudioPlayer>;

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
  return Math.min(1, Math.pow(raw * 3.5, 0.7));
}

function AudioSampler({ player, onLevel }: { player: AudioPlayerHandle; onLevel: (level: number) => void }) {
  useAudioSampleListener(player, (sample) => onLevel(rms(sample)));
  return null;
}

function WaveMark({ compact = false }: { compact?: boolean }) {
  const heights = compact ? [8, 14, 22, 30, 22, 14, 8] : [10, 18, 30, 42, 30, 18, 10];
  const colors = ['#0BB8F1', '#2384FF', '#655DF4', '#C63FF2', '#F13BB7', '#D842E6', '#8A4DF0'];
  return (
    <View style={[styles.waveMark, compact && styles.waveMarkCompact]}>
      {heights.map((height, index) => (
        <View key={index} style={[styles.waveMarkBar, { height, backgroundColor: colors[index] }]} />
      ))}
    </View>
  );
}

function BrandLogo() {
  return (
    <View style={styles.brandLogo}>
      <WaveMark compact />
      <Text style={styles.brandLogoText}>Studio Sat</Text>
      <Text style={styles.brandLogoTag}>A MÚSICA NOS CONECTA</Text>
    </View>
  );
}

function StationCard({ station, active, onPress }: { station: Station; active: boolean; onPress: () => void }) {
  const palette: Record<StationId, [string, string]> = {
    radioprincipal: ['#594DFF', '#E44AC5'],
    radiopop: ['#D83FD0', '#4B6CFF'],
    radiorock: ['#171A2A', '#334868'],
    radioclassicas: ['#B66B22', '#F0B85D'],
    radiocountry: ['#74431F', '#D09A52'],
  };
  return (
    <Pressable onPress={onPress} style={[styles.stationCardOuter, active && styles.stationCardOuterActive]}>
      <LinearGradient colors={palette[station.id]} style={styles.stationCard}>
        <WaveMark compact />
        <Text style={styles.stationCardLabel}>{station.shortName.toUpperCase()}</Text>
      </LinearGradient>
    </Pressable>
  );
}

function BottomTab({ icon, label, active, onPress }: { icon: string; label: string; active?: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={styles.bottomTab} accessibilityRole="button">
      <Text style={[styles.bottomTabIcon, active && styles.bottomTabActive]}>{icon}</Text>
      <Text style={[styles.bottomTabLabel, active && styles.bottomTabActive]}>{label}</Text>
    </Pressable>
  );
}

function formatLiveDuration(value?: number): string {
  if (!value || !Number.isFinite(value) || value <= 0) return 'AO VIVO';
  const total = Math.max(0, Math.round(value));
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

export default function App() {
  const [station, setStation] = useState<Station>(DEFAULT_STATION);
  const [now, setNow] = useState<NowPlaying>(emptyNow);
  const [carousel, setCarousel] = useState<CarouselItem[]>([]);
  const [metadataOnline, setMetadataOnline] = useState(false);
  const [vuLevel, setVuLevel] = useState(0);
  const [samplingAllowed, setSamplingAllowed] = useState(Platform.OS !== 'android');
  const [favorites, setFavorites] = useState<StationId[]>([]);
  const [muted, setMuted] = useState(false);
  const [sheet, setSheet] = useState<Sheet>(null);
  const [activeTab, setActiveTab] = useState<'home' | 'stations' | 'favorites' | 'more'>('home');
  const wasPlaying = useRef(false);
  const scrollRef = useRef<ScrollView>(null);

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
      setNow({ ...emptyNow, ...data, station: station.name });
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
    const metadata = {
      title: now.track || 'Programação ao vivo',
      artist: now.artist || station.name,
      albumTitle: station.name,
      artworkUrl: now.cover,
    };
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
      // A metadata do lock screen só é atualizada quando o player já está ativo.
    }
  }, [now.artist, now.cover, now.track, player, station.name, status.playing]);

  const chooseStation = useCallback(
    (next: Station) => {
      if (next.id === station.id) {
        setSheet(null);
        return;
      }
      wasPlaying.current = status.playing;
      player.pause();
      setStation(next);
      setNow({ ...emptyNow, station: next.name });
      setCarousel([]);
      setVuLevel(0);
      player.replace(next.streamUrl);
      setSheet(null);
      if (wasPlaying.current) setTimeout(() => player.play(), 180);
    },
    [player, station.id, status.playing],
  );

  const ensureSamplingPermission = useCallback(async (): Promise<boolean> => {
    if (Platform.OS !== 'android' || samplingAllowed) return true;
    return await new Promise<boolean>((resolve) => {
      Alert.alert(
        'VU em tempo real',
        'O Android exige permissão de áudio para liberar as amostras do som que o próprio app reproduz. A Studio Sat não grava nem envia o microfone.',
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

  const toggleFavorite = useCallback(() => {
    setFavorites((current) =>
      current.includes(station.id) ? current.filter((id) => id !== station.id) : [...current, station.id],
    );
  }, [station.id]);

  const toggleMute = useCallback(() => {
    const next = !muted;
    player.volume = next ? 0 : 1;
    player.muted = next;
    setMuted(next);
  }, [muted, player]);

  const isFavorite = favorites.includes(station.id);
  const translation = now.translationPtBr || now.translation;
  const cover = useMemo(() => now.cover, [now.cover]);
  const liveLabel = status.isBuffering ? 'CONECTANDO' : status.playing ? 'AO VIVO' : 'PAUSADO';
  const heroTitle = station.id === 'radioprincipal' ? 'Rádio\nStudio Sat' : `Studio Sat\n${station.shortName}`;
  const featuredStations = STATIONS;

  const showTab = (next: 'home' | 'stations' | 'favorites' | 'more') => {
    setActiveTab(next);
    if (next === 'home') {
      setSheet(null);
      scrollRef.current?.scrollTo({ y: 0, animated: true });
      return;
    }
    setSheet(next === 'stations' ? 'stations' : next === 'favorites' ? 'favorites' : 'more');
  };

  return (
    <SafeAreaView style={styles.safe}>
      {samplingAllowed && (
        <AudioSampler player={player} onLevel={(next) => setVuLevel((previous) => previous * 0.42 + next * 0.58)} />
      )}
      <StatusBar style="dark" />
      <View style={styles.app}>
        <ScrollView ref={scrollRef} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.header}>
            <Pressable style={styles.headerButton} onPress={() => setSheet('more')} accessibilityLabel="Abrir menu">
              <Text style={styles.headerMenuIcon}>☰</Text>
            </Pressable>
            <BrandLogo />
            <Pressable style={styles.profileButton} onPress={() => setSheet('more')} accessibilityLabel="Abrir opções">
              <Text style={styles.profileIcon}>●</Text>
            </Pressable>
          </View>

          <View style={styles.hero}>
            {cover ? <Image source={{ uri: cover }} style={StyleSheet.absoluteFill} resizeMode="cover" /> : null}
            <LinearGradient
              colors={cover ? ['rgba(23,28,66,0.20)', 'rgba(37,41,104,0.58)', 'rgba(24,27,72,0.96)'] : ['#716CF6', '#5B54D4', '#262C78']}
              locations={[0, 0.5, 1]}
              style={StyleSheet.absoluteFill}
            />
            <View style={styles.heroGlowA} />
            <View style={styles.heroGlowB} />

            <View style={styles.heroContent}>
              <View style={styles.heroLiveRow}>
                <View style={[styles.livePill, !status.playing && styles.livePillPaused]}>
                  <View style={styles.liveDot} />
                  <Text style={styles.liveText}>{liveLabel}</Text>
                </View>
                <Text style={styles.metadataState}>{metadataOnline ? 'METADATA AO VIVO' : 'TRANSMISSÃO AO VIVO'}</Text>
              </View>

              <Text style={styles.heroTitle}>{heroTitle}</Text>

              <View style={styles.nowRow}>
                <View style={styles.artistAvatar}>
                  {cover ? <Image source={{ uri: cover }} style={styles.artistAvatarImage} /> : <Text style={styles.artistAvatarText}>SS</Text>}
                </View>
                <View style={styles.nowCopy}>
                  <Text style={styles.nowArtist} numberOfLines={1}>{now.artist || station.name}</Text>
                  <Text style={styles.nowTrack} numberOfLines={1}>{now.track || 'Programação ao vivo'}</Text>
                </View>
                <Text style={styles.duration}>{formatLiveDuration(now.duration)}</Text>
              </View>

              <View style={styles.vuWrap}>
                <VuMeter level={status.playing && samplingAllowed ? vuLevel : 0} accent={station.accent} />
              </View>

              <View style={styles.controls}>
                <Pressable onPress={toggleFavorite} style={styles.controlGhost} accessibilityLabel="Favoritar emissora">
                  <Text style={[styles.heartIcon, isFavorite && styles.heartIconActive]}>{isFavorite ? '♥' : '♡'}</Text>
                </Pressable>
                <Pressable
                  style={styles.playButtonOuter}
                  onPress={togglePlayback}
                  accessibilityRole="button"
                  accessibilityLabel={status.playing ? 'Pausar rádio' : 'Ouvir rádio'}
                >
                  <LinearGradient colors={['#35BEFF', '#705CFF', '#E33DDA']} style={styles.playButton}>
                    {status.isBuffering ? <ActivityIndicator color="#FFFFFF" /> : <Text style={styles.playIcon}>{status.playing ? 'Ⅱ' : '▶'}</Text>}
                  </LinearGradient>
                </Pressable>
                <Pressable onPress={toggleMute} style={styles.controlGhost} accessibilityLabel={muted ? 'Ativar áudio' : 'Silenciar áudio'}>
                  <Text style={styles.volumeIcon}>{muted ? '×)))' : '◖))'}</Text>
                </Pressable>
              </View>
            </View>
          </View>

          <View style={styles.translationCard}>
            <View style={styles.translationIconBox}><Text style={styles.translationIcon}>译</Text></View>
            <View style={styles.translationCopy}>
              <Text style={styles.translationLabel}>TRADUÇÃO</Text>
              <Text style={styles.translationTitle}>{now.track || 'Música atual'}</Text>
              <Text style={translation ? styles.translationText : styles.translationEmpty} numberOfLines={3}>
                {translation || 'A tradução ou o contexto editorial da música atual aparecerá aqui quando o metadata da emissora fornecer esse conteúdo.'}
              </Text>
            </View>
            <Text style={styles.chevron}>›</Text>
          </View>

          <View style={styles.promoHeader}>
            <View>
              <Text style={styles.promoEyebrow}>STUDIO SAT AGORA</Text>
              <Text style={styles.promoTitle}>Conteúdo, notícia e publicidade</Text>
            </View>
            <Text style={styles.promoLive}>AO VIVO</Text>
          </View>
          <MediaCarousel items={carousel} accent={station.accent} />

          <View style={styles.stationHeader}>
            <Text style={styles.sectionTitle}>Nossas Emissoras</Text>
            <Pressable onPress={() => setSheet('stations')}><Text style={styles.seeAll}>Ver todas →</Text></Pressable>
          </View>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.stationCardsRow}>
            {featuredStations.map((item) => (
              <StationCard key={item.id} station={item} active={item.id === station.id} onPress={() => chooseStation(item)} />
            ))}
          </ScrollView>

          <View style={styles.bottomSpacer} />
        </ScrollView>

        <View style={styles.bottomNav}>
          <BottomTab icon="⌂" label="Início" active={activeTab === 'home'} onPress={() => showTab('home')} />
          <BottomTab icon="▦" label="Emissoras" active={activeTab === 'stations'} onPress={() => showTab('stations')} />
          <BottomTab icon={isFavorite ? '♥' : '♡'} label="Favoritos" active={activeTab === 'favorites'} onPress={() => showTab('favorites')} />
          <BottomTab icon="•••" label="Mais" active={activeTab === 'more'} onPress={() => showTab('more')} />
        </View>

        <Modal visible={sheet !== null} transparent animationType="slide" onRequestClose={() => { setSheet(null); setActiveTab('home'); }}>
          <Pressable style={styles.modalBackdrop} onPress={() => { setSheet(null); setActiveTab('home'); }}>
            <Pressable style={styles.modalSheet} onPress={() => undefined}>
              <View style={styles.modalHandle} />
              {sheet === 'stations' && (
                <>
                  <Text style={styles.modalTitle}>Cinco emissoras. Um só app.</Text>
                  <Text style={styles.modalSubtitle}>Escolha a emissora que deseja ouvir agora.</Text>
                  <View style={styles.modalStationList}>
                    {STATIONS.map((item) => (
                      <Pressable key={item.id} onPress={() => chooseStation(item)} style={[styles.modalStationRow, item.id === station.id && { borderColor: item.accent, backgroundColor: item.softAccent }]}>
                        <View style={[styles.modalStationDot, { backgroundColor: item.accent }]} />
                        <View style={{ flex: 1 }}>
                          <Text style={styles.modalStationName}>{item.name}</Text>
                          <Text style={styles.modalStationDesc}>{item.description}</Text>
                        </View>
                        <Text style={styles.chevron}>›</Text>
                      </Pressable>
                    ))}
                  </View>
                </>
              )}
              {sheet === 'favorites' && (
                <>
                  <Text style={styles.modalTitle}>Favoritos</Text>
                  <Text style={styles.modalSubtitle}>{favorites.length ? 'Suas emissoras favoritas.' : 'Você ainda não marcou nenhuma emissora como favorita.'}</Text>
                  {favorites.map((id) => {
                    const item = STATIONS.find((candidate) => candidate.id === id)!;
                    return (
                      <Pressable key={id} onPress={() => chooseStation(item)} style={styles.modalStationRow}>
                        <View style={[styles.modalStationDot, { backgroundColor: item.accent }]} />
                        <Text style={styles.modalStationName}>{item.name}</Text>
                      </Pressable>
                    );
                  })}
                </>
              )}
              {sheet === 'more' && (
                <>
                  <BrandLogo />
                  <Text style={styles.modalSubtitle}>A música nos conecta. Cinco rádios, conteúdo visual e reprodução contínua.</Text>
                  <Pressable style={styles.moreAction} onPress={() => Linking.openURL('https://www.radio.studiosatweb.com.br')}><Text style={styles.moreActionText}>Abrir portal Studio Sat</Text></Pressable>
                  <Pressable style={styles.moreAction} onPress={() => Linking.openURL('https://www.radio.studiosatweb.com.br/app/')}><Text style={styles.moreActionText}>Central de instalação</Text></Pressable>
                  <Pressable style={styles.moreAction} onPress={() => setSheet('stations')}><Text style={styles.moreActionText}>Trocar emissora</Text></Pressable>
                </>
              )}
            </Pressable>
          </Pressable>
        </Modal>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#F7F9FF',
    paddingTop: Platform.OS === 'android' ? RNStatusBar.currentHeight ?? 0 : 0,
  },
  app: { flex: 1, backgroundColor: '#F7F9FF' },
  content: { paddingHorizontal: 14, paddingTop: 8, paddingBottom: 24 },
  header: { height: 76, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  headerButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  headerMenuIcon: { fontSize: 28, color: '#50638C', lineHeight: 32 },
  profileButton: { width: 42, height: 42, borderRadius: 21, borderWidth: 1.5, borderColor: '#A8B6D4', alignItems: 'center', justifyContent: 'center' },
  profileIcon: { fontSize: 16, color: '#5D7097' },
  brandLogo: { alignItems: 'center', justifyContent: 'center' },
  brandLogoText: { fontSize: 25, lineHeight: 27, fontWeight: '900', letterSpacing: -1.2, color: '#172454' },
  brandLogoTag: { fontSize: 7, letterSpacing: 2.4, color: '#596B91', fontWeight: '700', marginTop: 2 },
  waveMark: { height: 46, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 3 },
  waveMarkCompact: { height: 24, gap: 2 },
  waveMarkBar: { width: 5, borderRadius: 99 },
  hero: { minHeight: 470, borderRadius: 27, overflow: 'hidden', backgroundColor: '#5259D9', borderWidth: 1, borderColor: 'rgba(255,255,255,0.55)', shadowColor: '#243473', shadowOpacity: 0.22, shadowRadius: 28, shadowOffset: { width: 0, height: 16 }, elevation: 8 },
  heroContent: { flex: 1, padding: 20, paddingTop: 18 },
  heroGlowA: { position: 'absolute', width: 190, height: 190, borderRadius: 95, backgroundColor: 'rgba(20,218,255,0.28)', right: -70, top: 80 },
  heroGlowB: { position: 'absolute', width: 170, height: 170, borderRadius: 85, backgroundColor: 'rgba(244,46,220,0.22)', left: -70, bottom: 30 },
  heroLiveRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  livePill: { flexDirection: 'row', alignItems: 'center', gap: 7, backgroundColor: '#FF2D55', borderRadius: 99, paddingHorizontal: 13, paddingVertical: 8, shadowColor: '#FF2D55', shadowOpacity: 0.35, shadowRadius: 10, shadowOffset: { width: 0, height: 4 } },
  livePillPaused: { backgroundColor: 'rgba(18,25,58,0.58)', shadowOpacity: 0 },
  liveDot: { width: 7, height: 7, borderRadius: 99, backgroundColor: '#FFFFFF' },
  liveText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900', letterSpacing: 0.5 },
  metadataState: { color: 'rgba(255,255,255,0.72)', fontSize: 8, fontWeight: '800', letterSpacing: 0.9 },
  heroTitle: { color: '#FFFFFF', fontSize: 42, lineHeight: 39, fontWeight: '900', letterSpacing: -2.2, marginTop: 26, maxWidth: '80%', textShadowColor: 'rgba(10,15,49,0.28)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 3 } },
  nowRow: { flexDirection: 'row', alignItems: 'center', marginTop: 'auto', marginBottom: 12 },
  artistAvatar: { width: 54, height: 54, borderRadius: 27, borderWidth: 2, borderColor: '#6FD8FF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center', backgroundColor: '#192B6D' },
  artistAvatarImage: { width: '100%', height: '100%' },
  artistAvatarText: { color: '#FFFFFF', fontSize: 16, fontWeight: '900' },
  nowCopy: { flex: 1, marginLeft: 12, marginRight: 8 },
  nowArtist: { color: '#FFFFFF', fontSize: 17, fontWeight: '900' },
  nowTrack: { color: 'rgba(255,255,255,0.88)', fontSize: 14, marginTop: 2, fontStyle: 'italic' },
  duration: { color: '#FFFFFF', fontSize: 12, fontWeight: '800' },
  vuWrap: { marginTop: 2, marginBottom: 10 },
  controls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-around', paddingHorizontal: 30, marginTop: 2 },
  controlGhost: { width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
  heartIcon: { color: '#FFFFFF', fontSize: 34, fontWeight: '300' },
  heartIconActive: { color: '#FF57C9' },
  playButtonOuter: { width: 84, height: 84, borderRadius: 42, padding: 3, borderWidth: 2, borderColor: 'rgba(255,255,255,0.88)', alignItems: 'center', justifyContent: 'center', shadowColor: '#6B60FF', shadowOpacity: 0.75, shadowRadius: 20, shadowOffset: { width: 0, height: 0 } },
  playButton: { width: 72, height: 72, borderRadius: 36, alignItems: 'center', justifyContent: 'center' },
  playIcon: { color: '#FFFFFF', fontSize: 27, fontWeight: '900', marginLeft: 2 },
  volumeIcon: { color: '#FFFFFF', fontSize: 20, fontWeight: '800' },
  translationCard: { marginTop: 12, backgroundColor: 'rgba(255,255,255,0.97)', borderRadius: 20, borderWidth: 1, borderColor: '#DAE1F2', padding: 14, flexDirection: 'row', alignItems: 'center', shadowColor: '#7B8CB7', shadowOpacity: 0.11, shadowRadius: 18, shadowOffset: { width: 0, height: 8 }, elevation: 2 },
  translationIconBox: { width: 40, height: 40, borderRadius: 12, backgroundColor: '#EEF3FF', borderWidth: 1, borderColor: '#CDD9F5', alignItems: 'center', justifyContent: 'center' },
  translationIcon: { color: '#4968AB', fontSize: 18, fontWeight: '800' },
  translationCopy: { flex: 1, marginHorizontal: 12 },
  translationLabel: { color: '#526DA8', fontSize: 9, letterSpacing: 1.1, fontWeight: '900' },
  translationTitle: { color: '#1F2C52', fontSize: 13, fontWeight: '900', marginTop: 2 },
  translationText: { color: '#53617E', fontSize: 12, lineHeight: 16, marginTop: 4 },
  translationEmpty: { color: '#7D879A', fontSize: 11, lineHeight: 15, marginTop: 4, fontStyle: 'italic' },
  chevron: { color: '#31538D', fontSize: 30, fontWeight: '300' },
  promoHeader: { marginTop: 18, marginBottom: 9, flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' },
  promoEyebrow: { color: '#56668A', fontSize: 9, letterSpacing: 1.4, fontWeight: '900' },
  promoTitle: { color: '#18244C', fontSize: 18, fontWeight: '900', marginTop: 3 },
  promoLive: { color: '#E53978', fontSize: 9, fontWeight: '900', letterSpacing: 1 },
  stationHeader: { marginTop: 20, marginBottom: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  sectionTitle: { color: '#19254E', fontSize: 20, fontWeight: '900', letterSpacing: -0.5 },
  seeAll: { color: '#405B99', fontSize: 12, fontWeight: '800' },
  stationCardsRow: { gap: 9, paddingRight: 12 },
  stationCardOuter: { width: 88, height: 92, borderRadius: 16, padding: 2, borderWidth: 2, borderColor: 'transparent' },
  stationCardOuterActive: { borderColor: '#5688FF' },
  stationCard: { flex: 1, borderRadius: 13, padding: 8, justifyContent: 'space-between', overflow: 'hidden' },
  stationCardLabel: { color: '#FFFFFF', fontSize: 11, fontWeight: '900', letterSpacing: -0.3, textShadowColor: 'rgba(0,0,0,0.25)', textShadowRadius: 4 },
  bottomSpacer: { height: 18 },
  bottomNav: { minHeight: 72, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-around', backgroundColor: 'rgba(255,255,255,0.98)', borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: '#D6DEEF', paddingBottom: Platform.OS === 'ios' ? 8 : 2 },
  bottomTab: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 8 },
  bottomTabIcon: { fontSize: 23, color: '#7481A1', fontWeight: '700' },
  bottomTabLabel: { color: '#7481A1', fontSize: 10, fontWeight: '700', marginTop: 2 },
  bottomTabActive: { color: '#2E64FF' },
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(15,22,48,0.38)', justifyContent: 'flex-end' },
  modalSheet: { backgroundColor: '#FFFFFF', borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingHorizontal: 18, paddingTop: 10, paddingBottom: 28, maxHeight: '78%' },
  modalHandle: { width: 46, height: 5, borderRadius: 99, backgroundColor: '#D8DEEA', alignSelf: 'center', marginBottom: 18 },
  modalTitle: { color: '#17234B', fontSize: 24, fontWeight: '900', letterSpacing: -0.7 },
  modalSubtitle: { color: '#6C768B', fontSize: 13, lineHeight: 19, marginTop: 6, marginBottom: 14 },
  modalStationList: { gap: 8 },
  modalStationRow: { minHeight: 62, flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 12, paddingVertical: 10, borderRadius: 16, borderWidth: 1, borderColor: '#E3E8F2', backgroundColor: '#FAFBFE' },
  modalStationDot: { width: 11, height: 11, borderRadius: 99 },
  modalStationName: { color: '#202B4B', fontSize: 14, fontWeight: '900' },
  modalStationDesc: { color: '#7B8497', fontSize: 11, marginTop: 2 },
  moreAction: { minHeight: 50, borderRadius: 15, borderWidth: 1, borderColor: '#DFE5F0', backgroundColor: '#F8FAFE', justifyContent: 'center', paddingHorizontal: 15, marginTop: 8 },
  moreActionText: { color: '#26365E', fontSize: 14, fontWeight: '800' },
});
