import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Station, StationId } from '../types';

export function StationSelector({
  stations,
  selected,
  onSelect,
}: {
  stations: Station[];
  selected: StationId;
  onSelect: (station: Station) => void;
}) {
  return (
    <View style={styles.shell}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.row}>
        {stations.map((station) => {
          const active = station.id === selected;
          return (
            <Pressable
              key={station.id}
              onPress={() => onSelect(station)}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              style={[styles.pill, active && { borderColor: station.accent, backgroundColor: station.softAccent }]}
            >
              <View style={[styles.dot, { backgroundColor: station.accent }]} />
              <Text numberOfLines={1} style={[styles.label, active && { color: station.accent, fontWeight: '800' }]}>
                {station.shortName}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: '#D9DEE7', backgroundColor: '#FFFFFF' },
  row: { gap: 8, paddingHorizontal: 16, paddingTop: 10, paddingBottom: 12 },
  pill: {
    minHeight: 36,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    paddingHorizontal: 12,
    borderRadius: 99,
    backgroundColor: '#F4F6F9',
    borderWidth: 1,
    borderColor: '#E5E9F0',
  },
  dot: { width: 7, height: 7, borderRadius: 99 },
  label: { fontSize: 12, color: '#4E5665', fontWeight: '700' },
});
