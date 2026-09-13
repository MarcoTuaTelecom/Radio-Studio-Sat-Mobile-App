import React, { useEffect, useMemo, useState } from 'react';
import { Image, StyleSheet, Text, View } from 'react-native';
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

export function MediaCarousel({ items, accent }: { items: CarouselItem[]; accent: string }) {
  const fallback = useMemo<CarouselItem[]>(
    () => [
      {
        id: 'fallback',
        type: 'image',
        url: '',
        eyebrow: 'PUBLICIDADE',
        headline: 'Música boa em todos os momentos',
        caption: 'Studio Sat — cinco rádios, uma só paixão.',
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

  return (
    <View style={styles.card}>
      {current.url ? (
        current.type === 'video' ? (
          <VideoCard item={current} />
        ) : (
          <Image source={{ uri: current.url }} style={StyleSheet.absoluteFill} resizeMode="cover" />
        )
      ) : (
        <LinearGradient colors={['#173C8B', '#7352E5', '#E149B8']} style={StyleSheet.absoluteFill} />
      )}
      <LinearGradient colors={['rgba(6,16,45,0.10)', 'rgba(8,20,48,0.82)']} style={StyleSheet.absoluteFill} />

      <View style={styles.badge}><Text style={styles.badgeText}>{current.eyebrow ?? (current.type === 'video' ? 'VÍDEO' : 'DESTAQUE')}</Text></View>
      <View style={styles.copy}>
        {!!current.headline && <Text style={styles.headline} numberOfLines={2}>{current.headline}</Text>}
        {!!current.caption && <Text style={styles.caption} numberOfLines={2}>{current.caption}</Text>}
      </View>
      <View style={styles.playCircle}><Text style={styles.playIcon}>▶</Text></View>
      <View style={styles.brand}><Text style={styles.brandWave}>▥</Text><Text style={styles.brandText}>Studio Sat</Text></View>
      <View style={styles.dots}>
        {slides.map((item, dotIndex) => (
          <View key={item.id} style={[styles.dot, dotIndex === index % slides.length && styles.dotActive]} />
        ))}
      </View>
      <View style={[styles.accentLine, { backgroundColor: accent }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  card: { height: 184, borderRadius: 22, overflow: 'hidden', backgroundColor: '#233C7A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.6)' },
  badge: { position: 'absolute', top: 12, left: 14, borderRadius: 7, borderWidth: 1, borderColor: 'rgba(255,255,255,0.75)', backgroundColor: 'rgba(17,26,64,0.66)', paddingHorizontal: 9, paddingVertical: 5 },
  badgeText: { color: '#FFFFFF', fontSize: 9, fontWeight: '900', letterSpacing: 0.7 },
  copy: { position: 'absolute', left: 16, right: 118, bottom: 30 },
  headline: { color: '#FFFFFF', fontSize: 21, lineHeight: 22, fontWeight: '900', letterSpacing: -0.6 },
  caption: { color: 'rgba(255,255,255,0.86)', fontSize: 11, lineHeight: 15, marginTop: 5 },
  playCircle: { position: 'absolute', width: 48, height: 48, borderRadius: 24, left: '50%', top: '50%', marginLeft: -24, marginTop: -24, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: 'rgba(45,55,126,0.46)', alignItems: 'center', justifyContent: 'center' },
  playIcon: { color: '#FFFFFF', fontSize: 18, marginLeft: 3 },
  brand: { position: 'absolute', right: 15, bottom: 24, alignItems: 'center' },
  brandWave: { color: '#8FE8FF', fontSize: 24, lineHeight: 24, fontWeight: '900' },
  brandText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  dots: { position: 'absolute', left: 0, right: 0, bottom: 9, flexDirection: 'row', justifyContent: 'center', gap: 6 },
  dot: { width: 6, height: 6, borderRadius: 99, backgroundColor: 'rgba(255,255,255,0.42)' },
  dotActive: { width: 17, backgroundColor: '#FFFFFF' },
  accentLine: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, opacity: 0.8 },
});
