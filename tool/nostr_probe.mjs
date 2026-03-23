#!/usr/bin/env node

const defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
];

const spotDiscoveryHashtag = 'spotapp';
const spotOrigin = 'spot';

function parseArgs(argv) {
  const opts = {
    relays: [...defaultRelays],
    timeoutSec: 90,
    sinceSec: 1800,
    keyword: '',
    generic: false,
    limit: 200,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--keyword' && i + 1 < argv.length) {
      opts.keyword = argv[++i];
      continue;
    }
    if (arg === '--timeout-sec' && i + 1 < argv.length) {
      opts.timeoutSec = Number(argv[++i]) || opts.timeoutSec;
      continue;
    }
    if (arg === '--since-sec' && i + 1 < argv.length) {
      opts.sinceSec = Number(argv[++i]) || opts.sinceSec;
      continue;
    }
    if (arg === '--relay' && i + 1 < argv.length) {
      opts.relays.push(argv[++i]);
      continue;
    }
    if (arg === '--limit' && i + 1 < argv.length) {
      opts.limit = Number(argv[++i]) || opts.limit;
      continue;
    }
    if (arg === '--generic') {
      opts.generic = true;
      continue;
    }
  }

  return opts;
}

function buildSummary(relay, event) {
  const tags = Array.isArray(event.tags) ? event.tags : [];
  const visibleTags = tags
    .filter((tag) => Array.isArray(tag) && tag[0] === 't' && tag[1] !== spotDiscoveryHashtag)
    .map((tag) => tag[1]);
  const markerD = tags.find((tag) => Array.isArray(tag) && tag[0] === 'd')?.[1] ?? '';
  const markerApp = tags.find((tag) => Array.isArray(tag) && tag[0] === 'app')?.[1] ?? '';
  const preview = String(event.content || '').replace(/\s+/g, ' ').trim().slice(0, 120);
  return {
    relay,
    id: event.id,
    pubkey: event.pubkey,
    created_at: event.created_at,
    tags: visibleTags,
    d: markerD,
    app: markerApp,
    preview,
  };
}

function matchesKeyword(event, keyword) {
  if (!keyword) return true;
  const haystacks = [
    event.id,
    event.pubkey,
    event.content,
    ...(Array.isArray(event.tags) ? event.tags.flat().map(String) : []),
  ]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase());
  return haystacks.some((value) => value.includes(keyword.toLowerCase()));
}

function isSpotEvent(event) {
  const tags = Array.isArray(event.tags) ? event.tags : [];
  const hasOriginMarker = tags.some(
    (tag) =>
      Array.isArray(tag) &&
      ((tag[0] === 'd' && tag[1] === spotOrigin) ||
        (tag[0] === 'app' && tag[1] === spotOrigin) ||
        (tag[0] === 't' && tag[1] === spotDiscoveryHashtag)),
  );
  return event.kind === 1 && hasOriginMarker;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const subId = `probe-${Date.now()}`;
  const since = Math.floor(Date.now() / 1000) - opts.sinceSec;
  const filter = {
    kinds: [1],
    since,
    limit: opts.limit,
  };
  if (!opts.generic) {
    filter['#t'] = [spotDiscoveryHashtag];
  }

  console.log(
    JSON.stringify(
      {
        action: 'subscribe',
        keyword: opts.keyword || null,
        generic: opts.generic,
        timeoutSec: opts.timeoutSec,
        filter,
        relays: opts.relays,
      },
      null,
      2,
    ),
  );

  const sockets = [];
  let resolved = false;
  let sawAny = false;

  const finish = (code) => {
    if (resolved) return;
    resolved = true;
    for (const ws of sockets) {
      try {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(['CLOSE', subId]));
        }
        ws.close();
      } catch {}
    }
    setTimeout(() => process.exit(code), 50);
  };

  const timer = setTimeout(() => {
    if (!sawAny) {
      console.error('timeout: no matching Spot events observed');
    } else {
      console.error('timeout: matching keyword not observed');
    }
    finish(1);
  }, opts.timeoutSec * 1000);

  for (const relay of opts.relays) {
    const ws = new WebSocket(relay);
    sockets.push(ws);

    ws.addEventListener('open', () => {
      ws.send(JSON.stringify(['REQ', subId, filter]));
    });

    ws.addEventListener('message', (message) => {
      let data;
      try {
        data = JSON.parse(String(message.data));
      } catch {
        return;
      }
      if (!Array.isArray(data) || data.length === 0) return;

      const [type, arg1, arg2, arg3] = data;

      if (type === 'EVENT') {
        const event = arg2;
        if (!event || !isSpotEvent(event)) return;
        sawAny = true;
        const summary = buildSummary(relay, event);
        console.log(JSON.stringify({ type: 'EVENT', summary }, null, 2));
        if (matchesKeyword(event, opts.keyword)) {
          clearTimeout(timer);
          console.log(JSON.stringify({ type: 'MATCH', relay, event }, null, 2));
          finish(0);
        }
        return;
      }

      if (type === 'EOSE') {
        console.log(JSON.stringify({ type: 'EOSE', relay, subId: arg1 }, null, 2));
        return;
      }

      if (type === 'NOTICE') {
        console.log(JSON.stringify({ type: 'NOTICE', relay, message: arg1 }, null, 2));
        return;
      }

      if (type === 'OK') {
        console.log(
          JSON.stringify(
            { type: 'OK', relay, eventId: arg1, accepted: arg2, message: arg3 },
            null,
            2,
          ),
        );
      }
    });

    ws.addEventListener('error', () => {
      console.error(`relay error: ${relay}`);
    });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
