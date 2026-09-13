import React from 'react';
import { StyleSheet, View } from 'react-native';

const PALETTE = ['#13C6F3', '#268CFF', '#5968FF', '#7D59F5', '#A64FEF', '#D244E3', '#F33BB9'];

export function VuMeter({ level, accent }: { level: number; accent: string }) {
  const bars = 24;
  const normalized = Math.max(0, Math.min(1, level));

  return (
    <View style={styles.row} accessibilityLabel={`Nível de áudio ${Math.round(normalized * 100)} por cento`}>
      {Array.from({ length: bars }, (_, index) => {
        const position = index / Math.max(1, bars - 1);
        const wave = 0.46 + 0.54 * Math.sin(position * Math.PI);
        const threshold = Math.max(0.06, position * 0.94);
        const active = normalized >= threshold;
        const height = 10 + wave * 28;
        const paletteIndex = Math.min(PALETTE.length - 1, Math.floor(position * PALETTE.length));
        const color = active ? PALETTE[paletteIndex] ?? accent : 'rgba(220,226,242,0.42)';

        return <View key={index} style={[styles.bar, { height, backgroundColor: color, opacity: active ? 1 : 0.72 }]} />;
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { height: 48, flexDirection: 'row', alignItems: 'center', gap: 3 },
  bar: { flex: 1, minWidth: 3, borderRadius: 99 },
});
