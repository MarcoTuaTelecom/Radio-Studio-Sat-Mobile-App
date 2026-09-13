import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

const PALETTE = [
  '#12D5F4', '#15BDF7', '#239BF8', '#357CF7', '#5269F6', '#6A5CF4',
  '#8054F2', '#9A4DEE', '#B548E9', '#CE43E2', '#E33DD5', '#F23CC1',
];

export function VuMeter({ level, accent }: { level: number; accent: string }) {
  const bars = 30;
  const normalized = Math.max(0, Math.min(1, level));

  const geometry = useMemo(
    () => Array.from({ length: bars }, (_, index) => {
      const x = index / Math.max(1, bars - 1);
      const envelope = 0.34 + 0.66 * Math.sin(Math.PI * x);
      const rhythm = 0.70 + 0.30 * Math.sin(index * 1.71 + 0.9);
      const resting = 7 + 16 * envelope * rhythm;
      return { x, resting };
    }),
    [],
  );

  return (
    <View style={styles.row} accessibilityLabel={`Nível de áudio ${Math.round(normalized * 100)} por cento`}>
      {geometry.map(({ x, resting }, index) => {
        const response = Math.pow(normalized, 0.72);
        const motion = 0.78 + 0.22 * Math.sin(index * 1.37 + normalized * 8.2);
        const height = Math.max(6, Math.min(43, resting + response * 24 * motion));
        const paletteIndex = Math.min(PALETTE.length - 1, Math.floor(x * PALETTE.length));
        const color = PALETTE[paletteIndex] ?? accent;
        return (
          <View
            key={index}
            style={[
              styles.bar,
              {
                height,
                backgroundColor: color,
                opacity: normalized > 0.025 ? 0.96 : 0.38,
              },
            ]}
          />
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    height: 50,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2.5,
  },
  bar: {
    flex: 1,
    minWidth: 2.5,
    maxWidth: 8,
    borderRadius: 99,
  },
});
