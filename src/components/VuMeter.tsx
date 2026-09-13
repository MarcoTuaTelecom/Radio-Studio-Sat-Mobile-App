import React from 'react';
import { StyleSheet, View } from 'react-native';

export function VuMeter({ level, accent }: { level: number; accent: string }) {
  const bars = 22;
  const normalized = Math.max(0, Math.min(1, level));
  return (
    <View style={styles.row} accessibilityLabel={`Nível de áudio ${Math.round(normalized * 100)} por cento`}>
      {Array.from({ length: bars }, (_, index) => {
        const threshold = (index + 1) / bars;
        const active = normalized >= threshold;
        const height = 8 + Math.sin((index / (bars - 1)) * Math.PI) * 24;
        return (
          <View
            key={index}
            style={[
              styles.bar,
              { height, backgroundColor: active ? accent : '#DDE2EA', opacity: active ? 1 : 0.75 },
            ]}
          />
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { height: 42, flexDirection: 'row', alignItems: 'center', gap: 3 },
  bar: { flex: 1, minWidth: 3, borderRadius: 99 },
});
