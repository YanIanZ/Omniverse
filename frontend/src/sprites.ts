// Original pixel art for the agent office. Agent and base furniture maps follow the
// Claude Design canvas "OmniMemo Pixel Office"; decor below is drawn for this app.
// Each character in a map is one pixel; '.' is transparent.

export type Palette = Record<string, string>
export type Run = { x: number; y: number; w: number; fill: string; cls?: string }

const BODY_A = [
  '...OOOOOO...',
  '..OHHHHHHO..',
  '.OHHkkHHHHO.',
  '.OHHhHHhHHO.',
  '.OHSSSSSSHO.',
  '.OSSESSESSO.',
  '.OSrSSSSrSO.',
  '..OSSssSSO..',
  '..OCCCCCCO..',
  '.OCCcCCcCdO.',
  '.OSCCCCCdSO.',
  '..OCCCCCdO..',
  '..OPPPPPPO..',
  '..OPPOOPPO..',
  '..OBBO.OBBO.',
  '..OOO..OOO..',
]
// Frame B: blink and hands forward on the keyboard. Shown only while a signal is fresh.
const BODY_B = BODY_A.map((row, y) =>
  y === 5 ? '.OSSOSSOSSO.' : y === 9 ? 'OSCCcCCcCdSO' : y === 10 ? '.OCCCCCCCdO.' : row,
)

const SKIN = { O: '#1a1423', S: '#f2c9a0', s: '#d9a27c', E: '#2b2233', r: '#e9a48a' }

const PROVIDERS: Record<string, Palette> = {
  claude: { H: '#d97757', h: '#a9533a', C: '#3b3f58', c: '#2a2d40', P: '#26283a', B: '#4a3a2a' },
  codex: { H: '#e8eef2', h: '#a9b6bf', C: '#1f8a8a', c: '#166868', P: '#2b2f3d', B: '#3a3a3a' },
  opencode: { H: '#2f2f36', h: '#55555f', C: '#4caf63', c: '#36854a', P: '#2b2f3d', B: '#3a3a3a' },
  gemini: { H: '#6c7cf0', h: '#4b58c4', C: '#e6e9ff', c: '#b8bfe8', P: '#3a3f66', B: '#2a2d40' },
}

// Unrecognised providers get a stable palette derived from their name.
const HAIR = ['#c98b4f', '#8b5e3c', '#d6c27a', '#9a6fb0', '#5f8fc4', '#c46a6a']
const COAT = ['#4a6fa5', '#8a5a9a', '#a5714a', '#4a8a7a', '#9a4a5a', '#5a6a8a']
function fallback(name: string): Palette {
  let h = 0
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0
  const hair = HAIR[h % HAIR.length]
  const coat = COAT[(h >>> 3) % COAT.length]
  return { H: hair, h: hair, C: coat, c: coat, P: '#2b2f3d', B: '#3a3a3a' }
}

/** Mix a #rrggbb colour toward white (amount > 0) or black (amount < 0). */
function tint(hex: string, amount: number) {
  const target = amount > 0 ? 255 : 0
  const a = Math.abs(amount)
  const ch = (i: number) => {
    const v = parseInt(hex.slice(i, i + 2), 16)
    return Math.round(v + (target - v) * a)
      .toString(16)
      .padStart(2, '0')
  }
  return `#${ch(1)}${ch(3)}${ch(5)}`
}

export function agentPalette(agent: string): Palette {
  const base = PROVIDERS[agent] ?? fallback(agent)
  // k: hair shine, d: coat shadow on the side away from the light.
  return { ...SKIN, ...base, k: tint(base.H, 0.35), d: tint(base.C, -0.3) }
}

export const AGENT_FRAMES = { a: BODY_A, b: BODY_B }

/** Compose a pixel map from filled rectangles: [x, y, w, h, char], later ops paint over earlier ones. */
function art(w: number, h: number, ops: [number, number, number, number, string][]): string[] {
  const grid = Array.from({ length: h }, () => Array<string>(w).fill('.'))
  for (const [x, y, rw, rh, ch] of ops)
    for (let j = y; j < Math.min(h, y + rh); j++) for (let i = x; i < Math.min(w, x + rw); i++) grid[j][i] = ch
  return grid.map((row) => row.join(''))
}

// Review wall screen: a static diff panel (decor, not data).
function diffScreen(): string[] {
  const ops: [number, number, number, number, string][] = [
    [0, 0, 100, 20, 'O'],
    [1, 1, 98, 18, 'f'],
    [2, 2, 96, 16, 'S'],
    [2, 2, 96, 1, 'H'],
    [3, 2, 1, 1, 'r'],
    [5, 2, 1, 1, 'y'],
    [7, 2, 1, 1, 'a'],
    [20, 3, 1, 15, 'H'],
    [2, 8, 18, 2, 's'],
  ]
  const tree = [9, 12, 7, 11, 8, 13, 6]
  tree.forEach((len, i) => ops.push([3 + (i % 3 === 1 ? 2 : 0), 4 + i * 2, len, 1, i === 2 ? 'x' : 'm']))
  const kinds = ['c', 'c', 'r', 'r', 'a', 'a', 'c']
  const words = [
    [14, 9, 20],
    [6, 18, 11],
    [10, 22],
    [16, 8, 9],
    [10, 24],
    [7, 12, 15],
    [18, 6],
  ]
  kinds.forEach((kind, i) => {
    const y = 4 + i * 2
    if (kind !== 'c') ops.push([22, y, 75, 2, kind === 'a' ? 'A' : 'R'])
    ops.push([23, y, 1, 1, kind === 'a' ? 'a' : kind === 'r' ? 'r' : 'g'])
    let x = 26
    for (const len of words[i]) {
      ops.push([x, y, len, 1, kind === 'a' ? 'a' : kind === 'r' ? 'r' : 'x'])
      x += len + 2
    }
  })
  ops.push([52, 16, 1, 1, 'C'])
  return art(100, 20, ops)
}

const PLANT_PALETTE = { g: '#1f5a2c', G: '#3f9150', L: '#6cc47a', O: '#3b2617', P: '#7a4e33', p: '#a8714c', r: '#c98d5f' }

export const FURNITURE = {
  monitor: {
    map: [
      '.OOOOOOOOOO.',
      'OhhhhhhhhhhO',
      'OkwSSSSSSSkO',
      'OkSbbbSyySkO',
      'OkSSSbbbbSkO',
      'OkSbbbbSSSkO',
      'OkSSSSSSSSkO',
      'OOOOOOOOOOOO',
      '....OmmO....',
      '...OmmmmO...',
    ],
    palette: { O: '#0b0d12', h: '#3c4559', k: '#2a3142', S: '#163c52', w: '#2a6a8a', b: '#5fd4ff', y: '#ffcf5c', m: '#3a4256' },
  },
  chair: {
    map: ['.OOOOOO.', 'OChhhhCO', 'OCCCCCCO', 'OCccccCO', 'OCCCCCCO', '.OOOOOO.', '.O.OO.O.'],
    palette: { O: '#11141b', h: '#56638a', C: '#3e4a66', c: '#2f3850' },
  },
  plantTop: {
    map: ['...g..g...', '..gLg.gLg.', '.gLGGgGLGg', 'gGLGgGGGg.', '.gGGGLGGg.', 'gGgGGGgGGg', '.gg.gg.gg.'],
    palette: PLANT_PALETTE,
  },
  plantPot: {
    map: ['.OOOOOOOO.', '.PrrrrrrP.', '..PppppP..', '..PpppPP..', '...PPPP...'],
    palette: PLANT_PALETTE,
  },
  sofa: {
    map: [
      '.OOOOOOOOOOOOOOOOOO.',
      'OAhhhhhhhhhhhhhhhhAO',
      'OAVVVVVVVVVVVVVVVVAO',
      'OAOOOOOOOOOOOOOOOOAO',
      'OAuuuuuuuOuuuuuuuuAO',
      'OAvvvvvvvOvvvvvvvvAO',
      'OOOOOOOOOOOOOOOOOOOO',
      '.dd..............dd.',
    ],
    palette: { O: '#1a1423', A: '#4f3a78', h: '#9a80d6', V: '#6b4fa0', u: '#8467c0', v: '#6b4fa0', d: '#0b0d12' },
  },
  coffee: {
    map: ['OOOOOOOO', 'OMhhhhMO', 'OMrMgMMO', 'OMMMMMMO', 'OMOOOOMO', 'OMO..OMO', 'OMOwwOMO', 'OMMMMMMO', 'OOOOOOOO'],
    palette: { O: '#11141b', M: '#5d6678', h: '#7c8494', r: '#ff6b5c', g: '#4fe07a', w: '#e9e2d6' },
  },
  rack: {
    map: [
      'OOOOOOOOOO',
      'OhhhhhhhhO',
      'OdLAdsssdO',
      'OkkkkkkkkO',
      'OdLAdsssdO',
      'OkkkkkkkkO',
      'OdLAdsssdO',
      'OkkkkkkkkO',
      'OdLAdsssdO',
      'OkkkkkkkkO',
      'OddddddddO',
      'OdTTTTTTdO',
      'OOOOOOOOOO',
      '.O......O.',
    ],
    // L (status) and A (activity) are replaced by the health colour at render time.
    palette: { O: '#07090d', h: '#3a4256', d: '#232935', k: '#171b24', s: '#0d1016', T: '#5a6478', L: '#4fe07a', A: '#4fe07a' },
  },
  bookshelf: {
    map: [
      'OOOOOOOOOO',
      'OhhhhhhhhO',
      'OwrbgwypcO',
      'OwrbgyypcO',
      'OwrbgyypcO',
      'OWWWWWWWWO',
      'OwcpwbbrgO',
      'OgcpybbrgO',
      'OgcpybbrgO',
      'OWWWWWWWWO',
      'OyyrwwgbpO',
      'OyyrgcgbpO',
      'OyyrgcgbpO',
      'OWWWWWWWWO',
      'OddddddddO',
      'OOOOOOOOOO',
    ],
    palette: {
      O: '#140e0a',
      h: '#8a6444',
      W: '#6b4a33',
      d: '#3a281c',
      w: '#2a1d15',
      r: '#b8483c',
      b: '#4a6fa5',
      g: '#4a8a5a',
      y: '#d6b04a',
      p: '#8a5a9a',
      c: '#e0d6c2',
    },
  },
  cooler: {
    map: [
      '..OOOO..',
      '.OBBBBO.',
      '.OBwBBO.',
      '.OBwBBO.',
      '.OBBBBO.',
      '..OBBO..',
      'OOOOOOOO',
      'OhhhhhhO',
      'OGGGGGGO',
      'OGrGGbGO',
      'OGGGGGGO',
      'OGooooGO',
      'OGGGGGGO',
      'OGGGGGgO',
      'OggggggO',
      'OOOOOOOO',
    ],
    palette: { O: '#11141b', B: '#4fa6d8', w: '#bfe8ff', G: '#c9ced8', h: '#e9edf3', g: '#8e96a6', r: '#ff6b5c', b: '#5fd4ff', o: '#5a616f' },
  },
  lamp: {
    map: [
      '.OOOO.',
      'OYYYYO',
      'OyyyyO',
      'OOOOOO',
      '..OO..',
      '..Op..',
      '..Op..',
      '..Op..',
      '..Op..',
      '..Op..',
      '..Op..',
      '..Op..',
      '..Op..',
      '.OOOO.',
      'OppppO',
      'OOOOOO',
    ],
    palette: { O: '#11141b', Y: '#ffe9b8', y: '#e0b860', p: '#5a616f' },
  },
  window: {
    map: [
      'OOOOOOOOOOOOOOOOO',
      'OnnsnnnnOnnnnnsnO',
      'OnnnnnnnOnnsnnnnO',
      'OkkkknkkOkknkkkkO',
      'OkykkkkkOkkkkykkO',
      'OkkkkykkOkykkkkkO',
      'OOOOOOOOOOOOOOOOO',
    ],
    palette: { O: '#3a4256', n: '#16223a', s: '#cfe3ff', k: '#0a0e16', y: '#ffcf5c' },
  },
  projector: {
    map: art(26, 9, [
      [0, 0, 26, 9, 'O'],
      [1, 1, 24, 7, 'w'],
      [3, 2, 9, 1, 't'],
      [4, 5, 2, 2, 'b'],
      [7, 4, 2, 3, 'b'],
      [10, 3, 2, 4, 'g'],
      [13, 4, 2, 3, 'b'],
      [17, 3, 6, 1, 'm'],
      [17, 5, 5, 1, 'm'],
      [3, 7, 13, 1, 'm'],
    ]),
    palette: { O: '#2b3142', w: '#dfe6ef', t: '#3a4256', b: '#5f8fc4', g: '#4fa35c', m: '#9aa3b8' },
  },
  corkboard: {
    map: art(32, 12, [
      [0, 0, 32, 12, 'O'],
      [1, 1, 30, 10, 'W'],
      [2, 2, 28, 8, 'c'],
      [4, 9, 1, 1, 'd'],
      [13, 8, 1, 1, 'd'],
      [27, 9, 1, 1, 'd'],
      [5, 8, 20, 1, 's'],
      [3, 3, 5, 5, 'y'],
      [4, 5, 3, 1, 't'],
      [4, 6, 2, 1, 't'],
      [9, 2, 5, 5, 'p'],
      [10, 4, 3, 1, 't'],
      [15, 4, 5, 5, 'g'],
      [16, 6, 3, 1, 't'],
      [21, 2, 5, 5, 'b'],
      [22, 4, 3, 1, 't'],
      [22, 5, 2, 1, 't'],
      [26, 4, 4, 5, 'y'],
      [27, 6, 2, 1, 't'],
      [5, 3, 1, 1, 'r'],
      [11, 2, 1, 1, 'r'],
      [17, 4, 1, 1, 'r'],
      [23, 2, 1, 1, 'r'],
      [28, 4, 1, 1, 'r'],
    ]),
    palette: {
      O: '#0b0d12',
      W: '#6b4a33',
      c: '#a87a4f',
      d: '#8f6540',
      s: '#c4473c',
      y: '#ffe08a',
      p: '#f2a0b8',
      g: '#a8e6a0',
      b: '#9fd0ff',
      t: '#5a4a3a',
      r: '#ff6b5c',
    },
  },
  cubbies: {
    map: art(24, 12, [
      [0, 0, 24, 12, 'O'],
      [1, 1, 22, 10, 'W'],
      [1, 1, 22, 1, 'h'],
      ...[2, 6, 10, 14, 18].flatMap((x) => [2, 5, 8].map((y): [number, number, number, number, string] => [x, y, 3, 2, 'k'])),
      [2, 3, 3, 1, 'e'],
      [10, 2, 3, 2, 'e'],
      [14, 3, 3, 1, 'f'],
      [6, 6, 3, 1, 'e'],
      [18, 5, 3, 2, 'f'],
      [2, 9, 3, 1, 'f'],
      [14, 8, 3, 2, 'e'],
    ]),
    palette: { O: '#0b0d12', W: '#6b4a33', h: '#8a6444', k: '#22170f', e: '#e9e2d6', f: '#d6b04a' },
  },
  kanban: {
    map: art(40, 7, [
      [0, 0, 40, 7, 'O'],
      [1, 1, 38, 5, 'w'],
      [13, 1, 1, 5, 'g'],
      [26, 1, 1, 5, 'g'],
      [2, 1, 10, 1, 'a'],
      [14, 1, 11, 1, 'y'],
      [27, 1, 11, 1, 'G'],
      [2, 3, 4, 2, 'b'],
      [7, 3, 4, 2, 'p'],
      [15, 3, 4, 2, 'y'],
      [20, 3, 4, 2, 'b'],
      [28, 3, 4, 2, 'G'],
      [33, 3, 4, 2, 'G'],
      [3, 6, 4, 1, 'm'],
      [9, 6, 2, 1, 'r'],
    ]),
    palette: {
      O: '#2b3142',
      w: '#dfe6ef',
      g: '#9aa3b8',
      a: '#7c8494',
      y: '#e0b040',
      G: '#4fa35c',
      b: '#9fd0ff',
      p: '#f2a0b8',
      m: '#5f8fc4',
      r: '#ff6b5c',
    },
  },
  wallscreen: {
    map: diffScreen(),
    palette: {
      O: '#0b0d12',
      f: '#2b3446',
      S: '#0e1a24',
      H: '#1d3446',
      s: '#173a52',
      m: '#3d5a70',
      x: '#7f9db5',
      g: '#3d5a70',
      A: '#12331f',
      a: '#4fe07a',
      R: '#3a1717',
      r: '#ff6b5c',
      y: '#ffcf5c',
      C: '#7fd4ff',
    },
  },
  tray: {
    map: art(10, 6, [
      [0, 0, 10, 6, 'O'],
      [1, 1, 8, 4, 'T'],
      [2, 1, 6, 3, 'w'],
      [2, 1, 6, 1, 'W'],
      [3, 2, 4, 1, 'l'],
    ]),
    palette: { O: '#0b0d12', T: '#5a6478', w: '#c9ced8', W: '#e9edf3', l: '#7c8494' },
  },
  stamp: {
    map: ['.OOO.', '.OrO.', '.OrO.', 'OOOOO', 'OkkkO', 'OOOOO'],
    palette: { O: '#11141b', r: '#c4473c', k: '#3a3f4c' },
  },
  paper: {
    map: art(7, 9, [
      [0, 0, 7, 9, 'O'],
      [1, 1, 5, 7, 'w'],
      [2, 2, 3, 1, 'l'],
      [2, 4, 3, 1, 'l'],
      [2, 6, 3, 1, 'i'],
    ]),
    palette: { O: '#2b3142', w: '#e9edf3', l: '#9aa3b8', i: '#5f8fc4' },
  },
  folder: {
    map: art(8, 6, [
      [1, 0, 3, 1, 'O'],
      [0, 1, 8, 5, 'O'],
      [1, 1, 6, 4, 'f'],
      [2, 1, 5, 1, 'w'],
      [1, 4, 6, 1, 'F'],
    ]),
    palette: { O: '#2a1d15', f: '#d6b04a', F: '#b08a30', w: '#e9edf3' },
  },
  laptop: {
    map: art(10, 7, [
      [0, 0, 10, 5, 'O'],
      [1, 1, 8, 3, 'S'],
      [2, 1, 4, 1, 'b'],
      [2, 3, 3, 1, 'b'],
      [0, 5, 10, 2, 'O'],
      [1, 5, 8, 1, 'K'],
    ]),
    palette: { O: '#11141b', S: '#163c52', b: '#5fd4ff', K: '#5a6478' },
  },
  mug: {
    map: ['OOOO..', 'OccOOO', 'OmmO.O', 'OmmOOO', 'OOOO..'],
    palette: { O: '#1a1423', c: '#5c3a20', m: '#e9e2d6' },
  },
  keyboard: {
    map: ['OOOOOOOOOO', 'OkKkKkKkKO', 'OOOOOOOOOO'],
    palette: { O: '#11141b', k: '#3a4256', K: '#5a6478' },
  },
  cabinet: {
    map: art(8, 14, [
      [0, 0, 8, 14, 'O'],
      [1, 1, 6, 12, 'g'],
      [1, 1, 6, 1, 'h'],
      [1, 5, 6, 1, 'O'],
      [1, 9, 6, 1, 'O'],
      [3, 3, 2, 1, 'k'],
      [3, 7, 2, 1, 'k'],
      [3, 11, 2, 1, 'k'],
      [6, 2, 1, 11, 'G'],
    ]),
    palette: { O: '#0b0d12', g: '#6a7388', h: '#8e98aa', G: '#4a5266', k: '#d5dbe8' },
  },
  fridge: {
    map: art(10, 16, [
      [0, 0, 10, 16, 'O'],
      [1, 1, 8, 14, 'F'],
      [1, 1, 8, 1, 'h'],
      [8, 1, 1, 14, 'f'],
      [1, 6, 8, 1, 'O'],
      [7, 3, 1, 2, 'k'],
      [7, 8, 1, 4, 'k'],
      [2, 9, 2, 2, 'p'],
      [4, 10, 2, 2, 'y'],
    ]),
    palette: { O: '#11141b', F: '#c9ced8', h: '#e9edf3', f: '#8e96a6', k: '#5a616f', p: '#ff6b5c', y: '#ffe08a' },
  },
  vending: {
    map: art(8, 16, [
      [0, 0, 8, 16, 'O'],
      [1, 1, 6, 14, 'V'],
      [1, 1, 6, 1, 'v'],
      [2, 2, 3, 9, 'g'],
      [2, 2, 3, 1, 'L'],
      [2, 4, 3, 1, 'a'],
      [2, 6, 3, 1, 'b'],
      [2, 8, 3, 1, 'c'],
      [2, 10, 3, 1, 'a'],
      [6, 3, 1, 1, 'k'],
      [6, 5, 1, 1, 'k'],
      [6, 7, 1, 1, 'k'],
      [2, 12, 4, 2, 'O'],
    ]),
    palette: {
      O: '#11141b',
      V: '#8a3a4a',
      v: '#b0566a',
      g: '#1d3446',
      L: '#7fd4ff',
      a: '#ffcf5c',
      b: '#4fa35c',
      c: '#f2a0b8',
      k: '#e9e2d6',
    },
  },
  fanA: {
    map: art(12, 10, [
      [0, 0, 12, 10, 'O'],
      [1, 1, 10, 8, 'G'],
      [1, 1, 10, 1, 'h'],
      [2, 2, 6, 6, 'k'],
      [4, 2, 2, 6, 'b'],
      [2, 4, 6, 2, 'b'],
      [4, 4, 2, 2, 'h'],
      [9, 2, 1, 1, 'k'],
      [9, 4, 1, 1, 'k'],
      [9, 6, 1, 1, 'k'],
    ]),
    palette: { O: '#0b0d12', G: '#8e96a6', h: '#c9ced8', k: '#1a1e28', b: '#5a616f' },
  },
  fanB: {
    map: art(12, 10, [
      [0, 0, 12, 10, 'O'],
      [1, 1, 10, 8, 'G'],
      [1, 1, 10, 1, 'h'],
      [2, 2, 6, 6, 'k'],
      [2, 2, 2, 1, 'b'],
      [3, 3, 1, 1, 'b'],
      [6, 2, 2, 1, 'b'],
      [6, 3, 1, 1, 'b'],
      [3, 6, 1, 1, 'b'],
      [2, 7, 2, 1, 'b'],
      [6, 6, 1, 1, 'b'],
      [6, 7, 2, 1, 'b'],
      [4, 4, 2, 2, 'h'],
      [9, 2, 1, 1, 'k'],
      [9, 4, 1, 1, 'k'],
      [9, 6, 1, 1, 'k'],
    ]),
    palette: { O: '#0b0d12', G: '#8e96a6', h: '#c9ced8', k: '#1a1e28', b: '#5a616f' },
  },
  ups: {
    map: art(8, 10, [
      [0, 0, 8, 10, 'O'],
      [1, 1, 6, 8, 'u'],
      [1, 1, 6, 1, 'h'],
      [2, 2, 4, 2, 'd'],
      [2, 2, 2, 1, 'c'],
      [2, 6, 4, 1, 's'],
      [2, 7, 4, 1, 's'],
    ]),
    palette: { O: '#0b0d12', u: '#3a4256', h: '#5a6478', d: '#10161f', c: '#7fd4ff', s: '#232935' },
  },
  extinguisher: {
    map: ['.kk.', 'kOOk', 'OrrO', 'OhrO', 'OrrO', 'OwwO', 'OrrO', 'OOOO'],
    palette: { k: '#3a3f4c', O: '#3a1010', r: '#c4473c', h: '#ff8a7a', w: '#e9e2d6' },
  },
  logo: {
    map: ['.OOOOOO.', 'OBBBBBBO', 'OBbBBbBO', 'OBBBBBBO', 'OBbbbbBO', 'OBBBBBBO', '.OOOOOO.'],
    palette: { O: '#d97757', B: '#2a2d40', b: '#ffcf5c' },
  },
} satisfies Record<string, { map: string[]; palette: Palette }>

export type FurnitureId = keyof typeof FURNITURE

export const LED = { on: '#4fe07a', off: '#55607a', fault: '#ff6b5c' }

/**
 * Horizontal runs of same-coloured pixels: far fewer SVG nodes than one rect per pixel.
 * `classes` tags the pixels of chosen map characters (e.g. screen text, LEDs) so CSS can
 * animate scenery; runs never merge across different classes.
 */
export function runs(map: string[], palette: Palette, classes?: Record<string, string>): Run[] {
  const out: Run[] = []
  map.forEach((row, y) => {
    let x = 0
    while (x < row.length) {
      const fill = palette[row[x]]
      if (!fill) {
        x++
        continue
      }
      const cls = classes?.[row[x]]
      let w = 1
      while (x + w < row.length && palette[row[x + w]] === fill && classes?.[row[x + w]] === cls) w++
      out.push(cls ? { x, y, w, fill, cls } : { x, y, w, fill })
      x += w
    }
  })
  return out
}
