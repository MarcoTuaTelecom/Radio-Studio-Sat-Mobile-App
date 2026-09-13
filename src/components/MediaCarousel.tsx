import React, { useEffect, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { VideoView, useVideoPlayer } from 'expo-video';
import { LinearGradient } from 'expo-linear-gradient';
import { CarouselItem } from '../types';

function VideoCard({ item }: { item: CarouselItem }) {
  const player = useVideoPlayer(item.url, (instance) => {
    instance.loop = true;
    instance.muted = true;
    instance.play();
  });
  return <VideoView player={player} style={StyleSheet.absoluteFill} contentFit="cover" nativeControls={false} />;
}

function MiniWave() {
  const heights = [7, 12, 18, 26, 18, 12, 7];
  return (
    <View style={styles.miniWave}>
      {heights.map((height, index) => (
        <View key={index} style={[styles.miniWaveBar, { height }]} />
      ))}
    </View>
  );
}

export function MediaCarousel({ items, accent }: { items: CarouselItem[]; accent: string }) {
  const fallback = useMemo<CarouselItem[]>(
    () => [
      {
        id: 'fallback',
        type: 'image',
        url: '',
        eyebrow: 'PUBLICIDADE',
        headline: 'Música boa\nem todos\nos momentos',
        caption: 'Viva mais música',
        durationMs: 10000,
      },
    ],
    [],
  );
  const slides = items.length ? items : fallback;
  const [index, setIndex] = useState(0);
  const current = slides[index % slides.length]!;

  useEffect(() => {
    setIndex((value) => value % slides.length);
  }, [slides.length]);

  useEffect(() => {
    const timer = setTimeout(() => setIndex((value) => (value + 1) % slides.length), current.durationMs ?? 9000);
    return () => clearTimeout(timer);
  }, [current.durationMs, slides.length]);

  const goNext = () => setIndex((value) => (value + 1) % slides.length);

  return (
    <View style={styles.card}>
      {current.url ? (
        current.type === 'video' ? (
          <VideoCard item={current} />
        ) : (
          <Image source={{ uri: current.url }} style={StyleSheet.absoluteFill} resizeMode="cover" />
        )
      ) : (
        <LinearGradient colors={['#153A82', '#7451DF', '#D94AB8']} style={StyleSheet.absoluteFill} />
      )}

      <LinearGradient
        colors={['rgba(7,15,42,0.02)', 'rgba(8,18,48,0.42)', 'rgba(7,17,45,0.88)']}
        locations={[0, 0.48, 1]}
        style={StyleSheet.absoluteFill}
      />

      <View style={styles.badge}>
        <Text style={styles.badgeText}>{current.eyebrow ?? (current.type === 'video' ? 'VÍDEO' : 'DESTAQUE')}</Text>
      </View>

      <View style={styles.copy}>
        {!!current.headline && <Text style={styles.headline} numberOfLines={3}>{current.headline}</Text>}
      </View>

      <Pressable onPress={goNext} style={styles.playCircle} accessibilityRole="button" accessibilityLabel="Próximo destaque">
        <Text style={styles.playIcon}>▶</Text>
      </Pressable>

      <View style={styles.rightCopy}>
        <Text style={styles.slogan} numberOfLines={2}>{current.caption || 'Viva mais música'}</Text>
        <MiniWave />
        <Text style={styles.brandText}>Studio Sat</Text>
      </View>

      <View style={styles.dots}>
        {slides.map((item, dotIndex) => (
          <Pressable key={item.id} onPress={() => setIndex(dotIndex)} accessibilityLabel={`Destaque ${dotIndex + 1}`}>
            <View style={[styles.dot, dotIndex === index % slides.length && styles.dotActive]} />
          </Pressable>
        ))}
      </View>

      <View style={[styles.accentLine, { backgroundColor: accent }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    height: 182,
    borderRadius: 22,
    overflow: 'hidden',
    backgroundColor: '#233C7A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.66)',
    shadowColor: '#30406B',
    shadowOpacity: 0.12,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 8 },
    elevation: 3,
  },
  badge: {
    position: 'absolute',
    top: 11,
    left: 13,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.80)',
    backgroundColor: 'rgba(17,26,64,0.70)',
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  badgeText: { color: '#FFFFFF', fontSize: 8, fontWeight: '900', letterSpacing: 0.65 },
  copy: { position: 'absolute', left: 15, right: 160, bottom: 27 },
  headline: { color: '#FFFFFF', fontSize: 20, lineHeight: 20, fontWeight: '900', letterSpacing: -0.55 },
  playCircle: {
    position: 'absolute',
    width: 48,
    height: 48,
    borderRadius: 24,
    left: '50%',
    top: '50%',
    marginLeft: -24,
    marginTop: -24,
    borderWidth: 2,
    borderColor: '#FFFFFF',
    backgroundColor: 'rgba(47,55,128,0.48)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  playIcon: { color: '#FFFFFF', fontSize: 18, marginLeft: 3, fontWeight: '900' },
  rightCopy: { position: 'absolute', right: 14, bottom: 21, width: 105, alignItems: 'flex-end' },
  slogan: { color: '#FFFFFF', fontSize: 18, lineHeight: 18, fontStyle: 'italic', fontWeight: '700', textAlign: 'right' },
  miniWave: { height: 28, flexDirection: 'row', alignItems: 'center', gap: 2, marginTop: 5 },
  miniWaveBar: { width: 3, borderRadius: 99, backgroundColor: '#B5F2FF' },
  brandText: { color: '#FFFFFF', fontSize: 11, fontWeight: '900', marginTop: -1 },
  dots: { position: 'absolute', left: 0, right: 0, bottom: 7, flexDirection: 'row', justifyContent: 'center', gap: 6 },
  dot: { width: 6, height: 6, borderRadius: 99, backgroundColor: 'rgba(255,255,255,0.42)' },
  dotActive: { width: 18, backgroundColor: '#FFFFFF' },
  accentLine: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, opacity: 0.82 },
});
