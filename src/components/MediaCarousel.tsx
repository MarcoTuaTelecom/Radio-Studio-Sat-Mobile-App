import React, { useEffect, useMemo, useState } from 'react';
import { Image, StyleSheet, Text, View } from 'react-native';
import { VideoView, useVideoPlayer } from 'expo-video';
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
        eyebrow: 'STUDIO SAT',
        headline: 'Informação, música e conteúdo em uma só experiência.',
        caption: 'Este box recebe vídeos, comerciais, notícias e chamadas da programação sem interromper a rádio.',
        durationMs: 10000,
      },
    ],
    [],
  );
  const slides = items.length ? items : fallback;
  const [index, setIndex] = useState(0);
  const current = slides[index % slides.length]!;

  useEffect(() => {
    const timer = setTimeout(() => setIndex((value) => (value + 1) % slides.length), current.durationMs ?? 9000);
    return () => clearTimeout(timer);
  }, [current.durationMs, slides.length]);

  return (
    <View style={styles.card}>
      {current.url ? (
        current.type === 'video' ? <VideoCard item={current} /> : <Image source={{ uri: current.url }} style={StyleSheet.absoluteFill} resizeMode="cover" />
      ) : (
        <View style={[StyleSheet.absoluteFill, styles.fallback, { backgroundColor: `${accent}14` }]} />
      )}
      <View style={styles.scrim} />
      <View style={styles.copy}>
        <Text style={styles.eyebrow}>{current.eyebrow ?? (current.type === 'video' ? 'VÍDEO' : 'DESTAQUE')}</Text>
        {!!current.headline && <Text style={styles.headline}>{current.headline}</Text>}
        {!!current.caption && <Text style={styles.caption}>{current.caption}</Text>}
      </View>
      <View style={styles.dots}>
        {slides.map((item, dotIndex) => (
          <View key={item.id} style={[styles.dot, dotIndex === index % slides.length && styles.dotActive]} />
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { height: 188, borderRadius: 24, overflow: 'hidden', backgroundColor: '#EAEFF7' },
  fallback: { backgroundColor: '#F3F6FB' },
  scrim: { position: 'absolute', top: 0, right: 0, bottom: 0, left: 0, backgroundColor: 'rgba(10,18,35,0.28)' },
  copy: { position: 'absolute', left: 18, right: 18, bottom: 24 },
  eyebrow: { color: '#FFFFFF', fontSize: 11, letterSpacing: 1.4, fontWeight: '900' },
  headline: { color: '#FFFFFF', fontSize: 20, lineHeight: 23, fontWeight: '900', marginTop: 6 },
  caption: { color: 'rgba(255,255,255,0.88)', fontSize: 12, lineHeight: 16, marginTop: 6, maxWidth: '92%' },
  dots: { position: 'absolute', left: 0, right: 0, bottom: 9, flexDirection: 'row', justifyContent: 'center', gap: 5 },
  dot: { width: 5, height: 5, borderRadius: 99, backgroundColor: 'rgba(255,255,255,0.45)' },
  dotActive: { width: 15, backgroundColor: '#FFFFFF' },
});
