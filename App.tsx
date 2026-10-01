import { useState } from 'react';
import { Button, StyleSheet, Text, View } from 'react-native';
import * as SQLite from 'expo-sqlite';

const ROUNDS = 400;
const CONCURRENCY = 50;

async function runStress(onProgress: (text: string) => void) {
  const db = await SQLite.openDatabaseAsync('stress.db');
  await db.execAsync(`
    DROP TABLE IF EXISTS items;
    CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT);
    INSERT INTO items (name) VALUES ('a'), ('b'), ('c');
  `);

  let calls = 0;
  let failures = 0;
  let otherErrors = 0;
  for (let round = 0; round < ROUNDS; round++) {
    const results = await Promise.allSettled(
      Array.from({ length: CONCURRENCY }, () => db.getAllAsync('SELECT * FROM items'))
    );
    calls += results.length;
    for (const result of results) {
      if (result.status === 'fulfilled') continue;
      const message = String(result.reason?.message ?? result.reason);
      if (message.includes('already released')) {
        failures++;
      } else {
        otherErrors++;
      }
      console.log(`[STRESS] failure: ${message}`);
    }
    if (round % 20 === 0) onProgress(`round ${round}/${ROUNDS}`);
  }
  await db.closeAsync();
  return { calls, failures, otherErrors };
}

export default function App() {
  const [status, setStatus] = useState('Idle');

  const onPress = async () => {
    setStatus('Running...');
    const { calls, failures, otherErrors } = await runStress(setStatus);
    const summary = `failures=${failures} calls=${calls} otherErrors=${otherErrors}`;
    console.log(`[STRESS] done ${summary}`);
    setStatus(summary);
  };

  return (
    <View style={styles.container}>
      <Button title="Run stress" onPress={onPress} />
      <Text testID="status" style={styles.status}>{status}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16 },
  status: { fontSize: 18 },
});
