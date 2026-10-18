# Product Requirements Document (PRD)
# OmniMemo — Universal AI Agent Memory & Context Optimization

**Versi:** 1.4  
**Tanggal:** 18 Oktober 2026  
**Status:** Proposed / Ready for Incremental Implementation (Memory Guardian + Guardrails + Mission Control + Omni Agent)  
**Model distribusi:** Local-first, offline-first, open-source core  
**Platform target:** macOS (Apple Silicon dan Intel), Linux x86_64/ARM64, Windows x86_64  
**Sasaran utama:** Codex, Claude Code, OpenCode, Gemini CLI, serta agent lain yang mendukung MCP dan/atau Agent Skills; Mission Control opsional; Omni Agent menambahkan delegasi lintas-runtime dan IDE  
**Nama produk:** OmniMemo (working title; dapat diganti sebelum peluncuran)

---

## 1. Executive Summary

OmniMemo adalah memory layer lokal yang persisten dan interoperabel bagi AI coding agent. Setiap agent yang terhubung membaca dan menulis ke satu penyimpanan memori yang sama, termasuk ringkasan sesi, keputusan arsitektur, progres implementasi, kesalahan yang pernah diperbaiki, preferensi teknis, dependency antar-modul, dan referensi sumber. Pengguna tidak perlu mengulang briefing panjang ketika berpindah dari Codex ke Claude Code, Gemini CLI, OpenCode, atau agent baru.

OmniMemo **bukan pengganti riwayat percakapan agent** dan **tidak dapat secara ajaib membaca history privat agent lain**. Sistem hanya mengingat informasi yang secara eksplisit disimpan, diindeks dari sumber yang diizinkan, atau diekstraksi melalui integrasi/hook yang tersedia dengan persetujuan pengguna. Penemuan dan pemulihan dilakukan on demand dengan token budget ketat, bukan menyuntikkan seluruh memori ke context window.

**Nilai utama:** satu sumber memori lintas-agent; token lebih efisien; penyimpanan kecil; tetap berfungsi offline; pemindahan database/cache ke SSD eksternal; transparansi sumber; keamanan dan kontrol memori penuh oleh pengguna.

## 2. Masalah Pengguna

| ID | Problem | Dampak |
|---|---|---|
| P-01 | Masing-masing agent memiliki sesi dan ingatan yang terfragmentasi | Briefing berulang ketika pindah agent |
| P-02 | Ringkasan konvensional tidak menunjukkan alasan dan hubungan keputusan | Kesalahan implementasi atau pengulangan keputusan lama |
| P-03 | Konteks awal memuat terlalu banyak file, log, serta instruksi | Biaya token, latensi, dan context pollution |
| P-04 | Beberapa solusi memerlukan cloud, embedding API, atau database terpisah | Dependensi, biaya, dan privasi |
| P-05 | Cache agent dan index membengkak di SSD internal | Ruang penyimpanan terpakai tanpa kontrol |
| P-06 | Memori proyek mudah basi setelah perubahan kode, branch, atau dependency | Jawaban keliru berdasarkan fakta usang |
| P-07 | Integrasi setiap agent berbeda | Konfigurasi berulang dan rentan rusak |

## 3. Visi, Goals, dan Non-goals

### 3.1 Visi

> Satu memory fabric yang dapat digunakan seluruh AI agent di satu mesin, dengan knowledge retrieval yang akurat, ringan, portabel, aman, dan adaptif terhadap kebutuhan tugas.

### 3.2 Goals

- G-01: Memori yang disimpan dari Agent A tersedia untuk Agent B sesaat setelah transaksi berhasil, jika izin dan scope memungkinkan.
- G-02: Pengambilan konteks relevan lewat satu atau sedikit tool call, dengan output token terukur.
- G-03: Berjalan **tanpa API key, cloud, GPU, model embedding, atau daemon permanen** pada konfigurasi dasar.
- G-04: Folder data dan cache bisa dialihkan serta dipindahkan dengan pemeriksaan integritas, rollback, dan pembaruan pointer otomatis.
- G-05: Backend native, storage lokal, dan maintenance dengan penggunaan RAM/disk rendah.
- G-06: Informasi memiliki asal-usul, relevansi, status validitas, dan relasi yang dapat ditelusuri.
- G-07: Instalasi agent berulang dapat dikendalikan dari satu CLI tanpa menduplikasi database.

### 3.3 Non-goals (v1)

- Mereplikasi atau menggabungkan history privat semua penyedia AI tanpa akses resmi.
- Menjanjikan persentase penghematan token pada setiap kasus.
- Melatih atau menjalankan LLM sendiri secara bawaan.
- Menggantikan Git, IDE indexer, semantic code search besar, atau database proyek produksi.
- Sinkronisasi multi-device real-time, kolaborasi tim lintas perangkat, dan SaaS sebagai prasyarat.
- Menyimpan seluruh chat/log/raw output secara otomatis tanpa persetujuan.

## 4. Persona dan Use Cases

**Persona A — Developer multi-agent:** mengerjakan satu repository lewat Claude, Codex, dan OpenCode secara bergantian. Butuh memori keputusan terbaru, progres, file terkait, bug penting, dan next steps.

**Persona B — Full-stack/multi-repository developer:** mengerjakan komponen panel, daemon, API, database, serta modul lain dengan beberapa agent. Butuh relasi dependensi lintas repository yang ditautkan secara eksplisit.

**Persona C — Developer dengan SSD eksternal:** membutuhkan lokasi database, indeks, dan cache di volume pilihan, termasuk prosedur aman saat SSD terlepas.

**Persona D — Maintainer OSS:** butuh bukti sumber, histori perubahan, serta kemampuan menolak memori yang sudah tidak sesuai branch/commit.

### Alur contoh end-to-end

1. Developer menjalankan `omnimemo init` dan `omnimemo install --agents codex,claude,opencode,gemini`.
2. Agent Codex menyimpan keputusan: "service backend memakai SQLite untuk metadata lokal" beserta file yang mendukung.
3. Developer menutup Codex dan membuka Claude Code pada project yang sama.
4. Claude memanggil `memory_context` dengan tugas, identitas project, dan `max_tokens=600`.
5. OmniMemo mengembalikan briefing ringkas plus referensi file dan status validitas, bukan seluruh dokumen.
6. Claude memperbarui implementasi dan menyimpan checkpoint dengan perubahan, hasil tes, serta pekerjaan berikutnya.
7. Gemini CLI dapat meminta `memory_recall` untuk keputusan terkait, tanpa membaca ulang seluruh riwayat sesi Codex/Claude.

## 5. Model Produk: Empat Lapisan

| Lapisan | Peran | Detail |
|---|---|---|
| Universal MCP Server | Antarmuka mesin-ke-agent | Tool read/write, resources opsional, stdio default; Streamable HTTP loopback opsional |
| Agent Skills | Perilaku lintas-agent | Discovery on demand, retrieve-before-repeat, save-after-milestone, handoff |
| Context & Memory Engine | Pemilihan memori | Budget tokenizer, ranking, dedup, staleness, relevance, provenance, graph neighbors |
| Portable Storage | Persistensi dan cache | SQLite + FTS5 + edge tables, disk cache bounded, blob archival optional |

Aliran data: Agent → Skill/policy → MCP tool → Context Engine → SQLite/FTS5/Graph → respons minimal → Agent. Semua agent menggunakan datastore yang sama; tidak mengkopi memori per agent.

## 6. Functional Requirements (Prioritas)

| ID | Prioritas | Fitur | Kriteria penerimaan |
|---|---|---|---|
| FR-01 | P0 | Shared Memory Store | Dua agent/dua proses MCP membaca satu record yang sama tanpa duplikasi |
| FR-02 | P0 | MCP stdio | Berjalan dengan CLI MCP compliant; stdout hanya protokol, logs ke stderr |
| FR-03 | P0 | Core Skills | Skill valid sesuai Agent Skills, terdeteksi pada empat agent utama |
| FR-04 | P0 | CRUD memory terstruktur | Membuat, membaca, memperbarui, mencari, mengarsipkan, dan menghapus secara terotorisasi |
| FR-05 | P0 | Context budget | `max_tokens` benar-benar membatasi keluaran; metadata tambahan ikut dihitung |
| FR-06 | P0 | FTS + retrieval relevan | Query bilingual/code symbol menemukan memo sesuai test set |
| FR-07 | P0 | Namespace/ACL | Tidak ada kebocoran memori private atau proyek lain |
| FR-08 | P0 | Portable data directory | `relocate` pindahkan DB+cache+index dengan verify, atomic cutover, rollback |
| FR-09 | P0 | Disk cache quota | LRU/TTL, batas ukuran, penghapusan otomatis dan `cache clear` |
| FR-10 | P0 | Proyek dan Git awareness | Project ID stabil, metadata repo/branch/worktree, warning pada ref yang tidak sesuai |
| FR-11 | P0 | Provenance | Memori menampilkan asal agent/file/commit/waktu dan confidence bila tersedia |
| FR-12 | P0 | Manual review / revoke | List, inspect, export, redact, delete, pin, mark stale, purge |
| FR-13 | P1 | Graph relationships | Entity/edge typed; query 1–2 hop dengan batas node/token |
| FR-14 | P1 | Structured checkpoints | Done, in progress, blocked, next steps, tests, changed paths |
| FR-15 | P1 | Auto-capture opt-in | Hook pada agent yang mendukung; bila tidak tersedia fallback manual/skill |
| FR-16 | P1 | Staleness detection | Hash/ref Git / file mtime per evidence, freshness scoring, invalidation |
| FR-17 | P1 | Setup manager | Deteksi agent, backup file konfigurasi, diff, uninstall idempotent |
| FR-18 | P1 | Stats/bench | Ringkasan pemakaian disk, hit ratio, context tokens, token delta vs baseline |
| FR-19 | P2 | Semantic retrieval optional | Model embedding lokal/pluggable; disabled by default; cache/model dibatasi terpisah |
| FR-20 | P2 | HTTP server | Loopback only, auth token, origin checks, rate limit, compatibility negotiation |
| FR-21 | P2 | Export/import portabel | Format JSONL versioned + Markdown, checksum, migrasi skema |
| FR-22 | P2 | Cross-repo links | Workspace ditautkan eksplisit, bukan otomatis menembus privacy boundary |

**Konvensi P0:** wajib untuk MVP; P1 untuk versi stabil berikutnya; P2 opsional.

## 7. Jenis dan Masa Hidup Memori

### 7.1 Kategori

1. `fact`: fakta terverifikasi tentang repositori, command build, konfigurasi.
2. `decision`: pilihan arsitektur, alasan, opsi yang ditolak, tanggal keputusan.
3. `task`: status pengerjaan, assignee agent, follow-up.
4. `issue`: bug, gejala, root cause, fix, regression test.
5. `preference`: konvensi yang memang disetujui pengguna, misalnya style Java/Gradle.
6. `insight`: temuan, hipotesis, pengalaman yang perlu divalidasi.
7. `checkpoint`: ringkasan terstruktur sesi atau milestone.
8. `entity`: representasi file, modul, service, API, package, repository.

### 7.2 Scope dan prioritas

- `session`: sementara, TTL pendek kecuali dipromosikan.
- `branch`: kontekstual terhadap branch/worktree; bisa diakses lintas branch dengan label warning.
- `project`: memori satu proyek, default untuk fakta kode.
- `workspace`: gabungan proyek yang telah ditautkan pengguna.
- `global`: preferensi umum yang pengguna pilih secara eksplisit.

Pada retrieval: filter izin → filter project → branch affinity → lexical relevance → freshness → evidence quality → importance → dedup → graph neighborhood → token packing. `global` tidak boleh mengalahkan keputusan project yang lebih baru dan spesifik.

### 7.3 State dan mutu

- Status: `active`, `unverified`, `stale`, `superseded`, `disputed`, `archived`.
- Provenance: asal file, path, hash, commit SHA, agent, session, timestamp, user-confirmed.
- Confidence: metadata kualitatif/terkalibrasi; tidak dianggap probabilitas faktual tanpa evaluasi.
- Konflik: simpan kedua klaim, tandai disputed, tampilkan alasan; jangan diam-diam menimpa.
- Hapus: hard-delete konten + edge, index, dan cache terkait. Backup terenkripsi berpotensi tetap mengandung salinan hingga rotasi; tampilkan hal ini di UI/CLI.

## 8. Lightweight Knowledge Graph

**Tidak memakai Neo4j atau graph service lain pada default.** Entity dan edge disimpan dalam SQLite.

**Entity types:** `repository`, `module`, `class`, `function`, `file`, `decision`, `issue`, `task`, `dependency`, `service`, `memory`.

**Edge types:** `RELATES_TO`, `DEPENDS_ON`, `IMPLEMENTS`, `DECIDED_FOR`, `FIXES`, `AFFECTS`, `BLOCKED_BY`, `SUPERSEDES`, `REFERENCES`, `BELONGS_TO`.

Contoh:

- `Decision: Redis untuk cache` → `DECIDED_FOR` → `Module: session-cache`.
- `Issue: stale auth` → `FIXES` → `Commit: abc123`.
- `Module: daemon` → `DEPENDS_ON` → `Module: API`.

**Query graph:** maksimal 1 hop secara default, 2 hop jika eksplisit; batas default 12 node/20 edge per response. Path harus menunjuk bukti valid, bukan otomatis dianggap kebenaran.

**Graph extraction default:** deterministik dari entitas yang ditulis, struktur proyek, dan source references. Ekstraksi konsep berbantuan LLM/embedding hanya opsional dan memiliki permission serta anggaran sendiri.

## 9. Token & Context Optimization

### 9.1 Strategi

- **On-demand retrieval:** jangan inject seluruh database atau historical conversation.
- **Progressive disclosure:** metadata skill kecil; instruksi penuh hanya ketika skill dipanggil.
- **Query first:** top-K pencarian dengan budget; jangan membaca repo penuh jika ringkasan cukup, tetapi tetap verifikasi file ketika mengubah kode.
- **Hierarchical memory:** satu-line gist → ringkasan → evidence/detail bila diminta.
- **Adaptive output:** mode `tiny` (100–200 token), `balanced` (300–700 token), `deep` (1000–2000 token); semua tunduk pada `max_tokens` eksplisit.
- **Delta handoff:** kembalikan hanya perubahan setelah checkpoint terakhir jika sudah pernah dibaca agent tersebut; tracking kursor bersifat advisory, tidak bergantung pada MCP protocol session.
- **Dedup:** hash normalized contents + similarity heuristic; update/revision daripada record salinan.
- **Stable tools:** hanya 5–6 tool utama dipublikasikan secara default; deskripsi singkat; advanced tools diaktifkan khusus.
- **Fail open untuk coding task:** jika memori tidak tersedia, agent tetap bekerja dari repository dan memberitahukan status memory unavailable.

### 9.2 Contract biaya token

`memory_context` harus melakukan budget enforcement sebelum mengirim respons: overhead JSON, label sumber, edge, teks memo, dan warning ikut dihitung. Tokenizer exact untuk provider yang mendukung; selain itu gunakan estimator konservatif dan toleransi terukur. Jika tidak muat, hapus detail secara bertahap, bukan memotong JSON secara acak.

**Contoh target evaluasi (bukan janji):** pengurangan median input tokens >= 30% pada benchmark cross-session berulang dibanding baseline tanpa OmniMemo, tanpa penurunan kualitas jawaban/tes; ukur pula overhead token skema MCP dan pemanggilan tool. Untuk pertanyaan sekali pakai, OmniMemo bisa tidak menghemat token.

## 10. MCP Contract dan Skills

### 10.1 Core tools (default)

| MCP tool | Input minimum | Output ringkas | Hak |
|---|---|---|---|
| `memory_context` | `{task, project?, max_tokens?, mode?}` | briefing, memo IDs, citations, stale flags, token estimate | read |
| `memory_recall` | `{query, project?, limit?, max_tokens?}` | ranked matches, snippets, provenance | read |
| `memory_get` | `{id, detail_level?}` | record terstruktur, edge/bukti sesuai kebutuhan | read |
| `memory_save` | `{type, title, content, scope?, project?, sources?, tags?}` | id, revision, disposition (created/merged/rejected) | write |
| `memory_checkpoint` | `{project?, done?, next?, blocked?, tests?, changed_files?}` | checkpoint id + handoff gist | write |
| `memory_status` | `{project?}` | connection, size, index state, cache, last updates | read |

### 10.2 Advanced tools (opt-in)

`memory_link`, `memory_invalidate`, `memory_export`, `memory_delete`, `memory_batch`, `memory_graph`, `memory_stats`. Destructive tools meminta konfirmasi pengguna sesuai kemampuan host; server tetap menegakkan ACL meski model mengabaikan skill. Pagination/cursor untuk query besar.

**Input contract umum:** `workspace_id` dan `project_id` jangan dipercaya mentah dari LLM; server mengikat request ke root/permission yang sudah diautorisasi. Tool return menyertakan `schema_version`, `result`, `source_refs`, `warnings`, `estimated_tokens`, dan `next_cursor` bila relevan. Seluruh operasi tulis idempotent via `idempotency_key` jika disediakan.

### 10.3 MCP compatibility

- `stdio` menjadi default karena paling mudah diintegrasikan ke CLI dan dapat memulai proses hanya saat diperlukan.
- Streamable HTTP loopback pilihan untuk satu server multi-client. **Implementasikan protocol version negotiation dan compatibility tests**, jangan mengasumsikan seluruh agent sudah mengadopsi revisi MCP terbaru.
- Hindari ketergantungan pada sesi MCP transport; jika butuh state, gunakan `cursor` dan `checkpoint_id` eksplisit.
- Log protokol terpisah dari stdout.
- Resource opsional: `omnimem://project/<id>/brief`, `omnimem://memory/<id>`; expose hanya jika client mendukung.

### 10.4 Skills resmi

| Skill | Trigger | Perilaku |
|---|---|---|
| `omnimem-recall` | Mengerjakan tugas lanjutan atau masuk ke repo yang pernah dikerjakan | Panggil memory_context terlebih dahulu; verifikasi informasi penting |
| `omnimem-capture` | Keputusan/fix/milestone penting muncul | Simpan pengetahuan ringkas dan sumber; jangan simpan chat mentah |
| `omnimem-handoff` | Berpindah agent atau menyelesaikan sesi | Simpan checkpoint done/next/blocked/tests |
| `omnimem-review` | Memori konflik, tidak akurat, atau tidak relevan | Tandai stale/disputed dan minta persetujuan untuk perbaikan |

Semua skills memakai `SKILL.md` standar dengan YAML frontmatter `name` dan `description`. Instruksi utama singkat, rincian di `references/` on demand. Host-specific hooks tidak ditanam pada SKILL.md umum; dihasilkan oleh adapter terpisah.

### 10.5 Matriks kompatibilitas integrasi

| Host | Skills path/strategi | MCP | Auto-capture |
|---|---|---|---|
| Codex | `.agents/skills/` + `AGENTS.md` minimal | Config Codex/CLI | Setelah milestone via skill; hook sesuai kemampuan resmi |
| Claude Code | `.claude/skills/` + `CLAUDE.md` minimal | Claude MCP scope user/project | Hook opt-in jika didukung |
| OpenCode | `.opencode/skills/` atau compatible `.agents/skills/` | `opencode.json` `mcp` | Plugin/hook jika API tersedia |
| Gemini CLI | `.gemini/skills/` atau `.agents/skills/` | `settings.json` `mcpServers` | Hook opt-in jika didukung |
| Agent lain | Native Agent Skills atau generated instruction adapter | Jika mendukung MCP, koneksikan; jika tidak, CLI fallback | Manual/fallback |

**Catatan penting:** "universal" berarti kemampuan inti portabel pada agent yang mendukung MCP/Skills/CLI. Tidak berarti semua web chatbot dapat mengakses folder lokal tanpa konektor/jembatan remote.

## 11. Storage, Cache, dan Portability

### 11.1 Technology decision

- **Core/server:** Rust native binary dengan dependency minimal; satu repositori dengan modul core, MCP, CLI, integrasi, dan test.
- **DB:** SQLite embedded + FTS5. Graph adjacency memakai tabel `entities` dan `edges`.
- **Default semantic retrieval:** lexical BM25 FTS5 + tag/symbol matcher + reranking aturan sederhana. Embeddings off.
- **Archival:** file JSONL terkompresi zstd opsional; jangan kompres seluruh DB sehingga FTS menjadi tidak dapat digunakan.
- **Cache:** bounded disk cache untuk query results/brief/index intermediate; in-memory LRU kecil; jangan menganggap database persisten sebagai cache yang boleh dihapus.
- **Daemon:** tidak wajib untuk stdio. Optional daemon untuk HTTP, watch mode, background compaction.

### 11.2 Struktur folder konseptual

    $OMNIMEM_HOME/
      meta.json
      db/
        memory.sqlite
      cache/
        retrieval/
        index/
      exports/
      backups/
      logs/

**Pointer konfigurasi kecil** ditaruh dalam direktori config OS (`XDG_CONFIG_HOME` atau ekuivalennya), menunjuk data root. Urutan resolusi: `--data-dir` → `OMNIMEM_HOME` → setting `data_dir` → default OS. Path harus dikanonisasi, diverifikasi ada, dan dapat ditulis. Gunakan UUID volume bila tersedia untuk mendeteksi volume berpindah mountpoint.

### 11.3 Policy disk dan RAM (target diuji pada benchmark)

- Disk cache default maksimal **32 MiB** (konfigurable `0–2048 MiB`), TTL default 24 jam, LRU eviction.
- RAM idle native process target **< 60 MiB** dan tanpa daemon saat tidak dipakai; kriteria ini tunduk pada pengujian lintas platform.
- Initial DB/metadata kosong target **< 10 MiB**; storage data persisten bertambah sesuai jumlah memo, bukan dicap sehingga tidak kehilangan informasi.
- Embedded vector index dan model downloads **nonaktif secara default**; apabila diaktifkan, kuota dan lokasinya terpisah serta dapat dihapus.
- `omnimem cache clear` aman menghapus cache tetapi tidak menyentuh data memori.
- WAL checkpoint/auto-vacuum berkala menjaga pertumbuhan file, tanpa menjalankan VACUUM agresif yang mengganggu penulisan.

### 11.4 Relocation transaction (wajib aman)

1. Preflight destination: ruang cukup, izin, path canonical, latensi, lock/file-system tests; identifikasi proses aktif.
2. Quiesce writes atau hentikan local server dengan protokol handshake; checkpoint WAL secara aman.
3. Salin folder ke target sementara, termasuk DB utama + journal/WAL yang diperlukan dan manifest checksum.
4. Verifikasi checksum, SQLite `PRAGMA integrity_check`, jumlah records, free space.
5. Atomic rename/cutover di destination, kemudian update pointer config; agent configuration menggunakan `omnimem` launcher stabil sehingga tidak perlu mengubah path di tiap agent.
6. Bila gagal, pointer tetap ke lokasi awal; jangan hapus sumber. Sediakan `--verify-only`, `--copy`, `--move`, `--rollback`.
7. Setelah sukses, simpan sumber sebagai backup sementara sampai user mengonfirmasi penghapusan atau melewati grace period.

**Kegagalan SSD eksternal:** jangan otomatis membuat database baru kosong di SSD internal. Kembalikan `storage_unavailable` dan tawarkan `read-only`, reconnect, atau failover yang dipilih pengguna. Tidak boleh diam-diam melakukan sync balik yang berisiko konflik.

**Filesystem:** SQLite WAL direkomendasikan untuk storage lokal dengan dukungan locking yang benar. Network filesystem tidak didukung untuk mode multi-process WAL. Periksa karakteristik APFS/ext4/NTFS/exFAT; jika kemampuan locking tidak memenuhi syarat, gunakan single-writer strategy atau tampilkan unsupported mode, jangan menjanjikan keamanan concurrency.

## 12. Data Model dan Indeks

**Table `memories`:** `id UUID`, `workspace_id`, `project_id`, `branch`, `worktree_id`, `scope`, `kind`, `title`, `summary`, `body`, `state`, `priority`, `confidence`, `created_at`, `updated_at`, `expires_at`, `revision`, `author_agent`, `session_ref`, `content_hash`, `acl_id`.

**Table `sources`:** `id`, `memory_id`, `source_type`, `repo_id`, `file_path`, `git_commit`, `file_hash`, `line_start`, `line_end`, `retrieved_at`, `verified_at`.

**Table `entities`:** `id`, `type`, `canonical_key`, `name`, `project_id`, `metadata`.

**Table `edges`:** `id`, `src_entity_id`, `dst_entity_id`, `relation`, `evidence_memory_id`, `state`, `created_at`.

**Table `checkpoints`:** `id`, `project_id`, `session_ref`, `agent`, `done_json`, `next_json`, `blocked_json`, `tests_json`, `changed_paths_json`, `created_at`.

**Table `acl`, `projects`, `workspaces`, `agent_installations`, `schema_migrations`, `audit_events`.**

**FTS5:** index `title`, `summary`, `body`, `tags`; jangan membiarkan deleted content tertinggal dalam cache/search; atomic update FTS index saat CRUD. Gunakan migrasi skema versioned dengan backup pre-migration dan forward-compat checks.

## 13. CLI, Config, dan Developer UX

### 13.1 CLI yang harus tersedia

    omnimem init --data-dir /Volumes/DevSSD/AI-Memory
    omnimem install --agents codex,claude,opencode,gemini --scope user
    omnimem doctor
    omnimem status
    omnimem project attach .
    omnimem memory search "auth session cache"
    omnimem memory list --project current
    omnimem memory show <id>
    omnimem memory pin <id>
    omnimem memory delete <id>
    omnimem context "lanjutkan migrasi auth" --max-tokens 500
    omnimem checkpoint --interactive
    omnimem cache info
    omnimem cache clear
    omnimem config set cache.max_size_mib 32
    omnimem relocate /Volumes/OtherSSD/AI-Memory --move --verify
    omnimem export --format jsonl --output backup.jsonl
    omnimem uninstall --agents all --keep-data

**Perintah di atas adalah spesifikasi target, bukan klaim bahwa binary sudah dibuat.** Installer harus menampilkan diff konfigurasi dan membuat backup; tidak boleh menimpa blok pengaturan lain pada `config.toml`, `settings.json`, `opencode.json`, atau `.mcp.json`.

### 13.2 Contoh konfigurasi target (`config.toml`)

    [storage]
    data_dir = "/Volumes/DevSSD/AI-Memory"
    sqlite_journal_mode = "auto"
    encrypt_at_rest = false

    [cache]
    max_size_mib = 32
    ttl_hours = 24
    memory_lru_entries = 64

    [retrieval]
    mode = "balanced"
    default_max_tokens = 500
    max_results = 8
    graph_hops = 1
    embedding_backend = "disabled"

    [capture]
    mode = "manual_or_skill"
    store_raw_chat = false
    require_provenance = true

    [security]
    remote_http_enabled = false
    cross_project_access = "deny"
    redact_secrets = true

**Penerapan path:** bisa memakai konfigurasi global pointer dan env. Semua agent menjalankan perintah executable stabil `omnimem mcp serve --stdio`; binary mengetahui lokasi DB melalui pointer; tidak menyimpan path volume di file setiap agent.

## 14. Security, Privacy, dan Governance

- **Default deny:** tidak ada akses cross-project/cross-workspace, raw chat, cloud API, dan remote MCP tanpa izin eksplisit.
- **MCP authorization:** agent identity yang diklaim dalam tool args tidak boleh menjadi faktor autentikasi. Gunakan per-installation credentials atau policy host, canonical project roots, serta akses least privilege.
- **Injection resistance:** memory/body/source dianggap untrusted data; tidak boleh dieksekusi sebagai instruksi. SKILL.md trusted dan catatan hasil search berbeda trust level.
- **Sensitive content:** regex secret detection + entropy heuristics + allow/deny patterns; jangan menyimpan token, password, cookie, private key, `.env`, kredensial, atau isi folder terlarang. False positives diselesaikan via review pengguna.
- **Paths:** canonicalize, reject traversal dan symlink escape di luar root authorized; rahasia path lokal disingkat di output bila perlu.
- **Encryption:** opsi enkripsi-at-rest untuk DB/backups (implementasi driver / encrypted volume yang sesuai); jangan menyebut SQLite dasar terenkripsi secara otomatis. Credential kunci ditaruh di OS keychain, bukan config plaintext.
- **Audit:** append-only metadata perubahan penting, redacted by default. Undo/revisions untuk memori penting.
- **Retention:** TTL per jenis memori, ekspor, penghapusan permanen, rotasi backup. Pengguna dapat mematikan telemetry sepenuhnya (default: off).
- **HTTP security (opsional):** bind 127.0.0.1, auth, origin validation, CSRF/DNS rebinding protections, rate limiting. Multi-device cloud sync memerlukan desain otorisasi berbeda.
- **Installer:** backup/diff/restore; tidak memodifikasi AGENTS.md, CLAUDE.md, GEMINI.md, atau config lain tanpa review dan izin.

## 15. Reliability, Observability dan Non-functional Requirements

| NFR | Target MVP | Pengujian |
|---|---|---|
| NFR-01 Read latency | p95 `memory_context` < 150 ms pada DB 10k memori, tanpa embeddings, warm cache | benchmark lokal mid-range |
| NFR-02 Write latency | p95 `memory_save` < 250 ms | benchmark SQLite local SSD |
| NFR-03 Resource idle | < 60 MiB RAM saat proses berjalan idle; 0 proses resident pada stdio idle | process monitor |
| NFR-04 Cache | ≤ 32 MiB default (toleransi overhead filesystem kecil) | saturate cache tests |
| NFR-05 Correctness | Tidak ada hilangnya data dari 10k concurrent/interleaved ops simulasi | WAL, crash/recovery tests |
| NFR-06 Portability | Relocation menjaga hash dan count 100% setelah verifikasi | macOS/Linux/Windows matrix |
| NFR-07 Isolation | 0 hasil dari project private lain tanpa akses | ACL/adversarial tests |
| NFR-08 Availability | MCP failure tidak memblokir tugas coding normal | disconnect tests |
| NFR-09 API stability | versioned schemas + contract tests + compatibility negotiation | multi-client fixtures |
| NFR-10 Quality | Recall@5 >= 0.85 pada golden benchmark internal, disertai precision/stale rate | labeled queries |

Angka di atas adalah **target engineering yang harus divalidasi**, bukan hasil benchmark yang sudah dicapai. Simpan baseline hardware, jumlah/ukuran records, cold/warm runs, p50/p95/p99, serta reproducible scripts.

## 16. Cross-Agent and Token-Saving Acceptance Tests

**AT-01 — Codex → Claude:** simpan decision lewat Codex, hentikan, buka Claude pada proyek yang sama, `memory_recall` menampilkan decision ID, isi, dan sumber dalam <= 2 panggilan.

**AT-02 — Claude → Gemini:** buat checkpoint dari Claude, buka Gemini dan minta `memory_context`; progress dan next steps tampil tanpa mengulang briefing pengguna.

**AT-03 — Multi-process writes:** 4 agent/server stdio paralel melakukan operasi tulis; transaksi konsisten, revisions terurut, integrity_check sukses, duplicate handling idempotent.

**AT-04 — Isolation:** agent yang berada di repo B tidak boleh memperoleh private memory repo A lewat query, scope spoofing, atau crafted path.

**AT-05 — Disk relocation:** saat berhenti idle, pindahkan 1 GB dataset dari internal SSD ke external SSD; checksum, count, index, ACL, config, dan akses host tetap benar; rollback valid.

**AT-06 — Drive unplugged:** external SSD dilepas; server mengembalikan `storage_unavailable`, tidak membuat shadow DB internal, dan tidak merusak data.

**AT-07 — Stale decisions:** ubah file yang terkait decision, atau berpindah ke branch incompatible; hasil harus menunjukkan warning; detail perlu verifikasi sebelum dianggap authoritative.

**AT-08 — Secret filter:** upsert token/API key sintetis ditolak atau diredaksi; raw content tidak muncul di DB/cache/log/exports.

**AT-09 — Budget:** 100 query dengan budget 200/500/1000 token; tidak ada respons yang melewati bound yang dikontrak, termasuk metadata dan source refs.

**AT-10 — Token ROI:** ukur fixed 30-task suite pada (a) no-memory, (b) text brief static, (c) OmniMemo. Ukur token input/output/tool, task success, hallucinated references, latency, biaya jika tersedia. Jangan mengklaim hemat jika total biaya/quality tidak mendukung.

**AT-11 — Install/uninstall idempotence:** run install dua kali, tidak menduplikasi entri MCP/skills, uninstall mengembalikan konfigurasi yang dibuat aplikasi tanpa menghapus setting orang lain.

## 17. Roadmap / Milestone

**M0 — Discovery + Spike (1 minggu):** matrix versi setiap agent; benchmark SQLite/FTS5 di volume internal/eksternal; protokol MCP 2026-07-28 dan fallback compatibility; skema memori dan dataset uji.

**M1 — MVP Core (2–3 minggu):** Rust CLI, SQLite migrations, projects/scopes, save/get/recall/context, MCP stdio, FTS5, token budget, installer empat agent, 2 skills (`recall` dan `handoff`), cache bounded, basic security.

**M2 — Portable Stable Beta (2 minggu):** relocation transaction, verification + rollback, concurrent tests, source provenance, checkpoint, review/delete/export, doctor, benchmarking, Git awareness, threat tests.

**M3 — v1.0 (2–3 minggu):** graph entities/edges, 4 skills, sophisticated invalidation, plugin/hook opt-in, packaging dan release macOS/Linux/Windows, comprehensive CI + docs.

**M4 — Future:** embeddings/model lokal, HTTP server hardened, multi-project graph, optional encrypted sync/team sharing, selective repository indexer, optional advanced UI/TUI.

Estimasi adalah rencana engineering awal dan harus direvisi setelah spike; bukan janji waktu delivery.

## 18. Repository / Code Structure

    omnimemo/
      Cargo.toml
      crates/
        omnimem-core/        # memory use-cases, validation, ranking, token budgets
        omnimem-storage/     # SQLite, migrations, FTS, backup
        omnimem-graph/       # entities, edges, graph retrieval
        omnimem-mcp/         # protocol tools, resources, transports
        omnimem-cli/         # binary commands and UX
        omnimem-adapters/    # Codex / Claude / OpenCode / Gemini config
        omnimem-security/    # ACL, redaction, policy
      skills/
        omnimem-recall/SKILL.md
        omnimem-capture/SKILL.md
        omnimem-handoff/SKILL.md
        omnimem-review/SKILL.md
      docs/
        architecture.md
        mcp-contract.md
        storage-and-relocation.md
        threat-model.md
        compatibility-matrix.md
        benchmarks.md
      tests/
        fixtures/
        cross-agent/
        crash-recovery/
        performance/
      .github/workflows/

**Development rules:** no mandatory network, deterministic tests, strictly versioned DB migrations, automated release binaries, no agent name written as Git commit author without user's explicit approval, backward compatibility test for every MCP adapter.

## 19. Risks, Tradeoffs, dan Mitigations

| Risiko | Probabilitas | Mitigasi |
|---|---|---|
| Agent tidak otomatis memanggil skill | Sedang | Instruction adapter minimal, eksplisit manual command, host hooks hanya opt-in |
| MCP tool schema menambah biaya token | Sedang | 6 tool default, stable concise schemas, deferred advanced tools, benchmark full cost |
| SQLite locking bermasalah di removable/exFAT | Sedang | Preflight, single-writer fallback, unsupported fs warning, crash tests |
| Memori salah/usang dianggap authoritative | Tinggi | Evidence, Git-aware warning, state disputed/stale, verification before code edits |
| Memori pribadi bocor antar proyek | Tinggi | Default-deny, authorized roots, scoped ids server-side, adversarial tests |
| Sensitive data tersimpan | Tinggi | Redaction, denylist, source allowlist, opt-in capture, secure delete semantics |
| File konfigurasi agent rusak | Sedang | Parser-aware patches, preview diff, backup and exact uninstall |
| Semantic search membengkakkan cache/model | Sedang | Off by default, separate quotas, explicit download/clean controls |

## 20. Definition of Done / Launch Gate

MVP dianggap siap dipakai bila:

- Codex, Claude Code, OpenCode, dan Gemini CLI berhasil tersambung ke store yang sama dengan test resmi.
- Perpindahan agent mempertahankan memori dan checkpoint dengan scope serta evidence yang benar.
- Cache disk terikat kuota, operasi `cache clear` tidak merusak memori.
- Pemindahan ke external SSD lulus checksum, integrity, rollback, dan unplug tests.
- User bisa inspect/export/delete seluruh data; secrets tidak disimpan dalam pengujian.
- Tidak perlu database service, model embedding, API key, atau daemon terus-menerus.
- Documented benchmark memperlihatkan ROI token dan kualitas, termasuk kasus rugi/no benefit.
- Dokumentasi instalasi, migrasi, keamanan, compatibility dan troubleshooting lengkap.

## 21. Referensi Teknis (diakses 18 Oktober 2026)

- MCP Specification 2026-07-28 dan changelog: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx
- MCP 2026-07-28 announcement: https://blog.modelcontextprotocol.io/posts/2026-07-28/
- Agent Skills specification: https://agentskills.io/specification
- OpenAI MCP configuration example: https://developers.openai.com/learn/docs-mcp
- OpenAI skills usage: https://developers.openai.com/blog/skills-agents-sdk
- Claude Code features (Skill + MCP differentiation): https://code.claude.com/docs/id/features-overview
- OpenCode skills: https://opencode.ai/v2/docs/skills
- OpenCode MCP: https://docs.opencode.ai/docs/mcp-servers/
- Gemini CLI skills: https://geminicli.com/docs/cli/skills/
- Gemini CLI MCP: https://geminicli.com/docs/tools/mcp-server/
- SQLite WAL behavior/limitations: https://www.sqlite.org/wal.html
- Graphify conceptual inspiration: https://www.graphiffy.com/docs

---

**Prinsip inti:** jangan memaksa AI mengingat semuanya. Simpan pengetahuan yang penting dengan sumber yang dapat diverifikasi, lalu ambil sedikit konteks yang paling relevan ketika dibutuhkan—di semua agent, melalui satu storage yang dapat dikendalikan pemiliknya.

---

## 22. Solution Architecture — OmniMemo Memory Guardian (v1.1)

### 22.1 Design thesis

**OmniMemo bukan chat transcript database.** Sistem adalah _evidence-aware memory broker_: menerima catatan singkat dan terstruktur dari agent, memverifikasi asal dan ruang lingkup, mendeteksi kontradiksi, mengatur akses baca/tulis, lalu menyajikan konteks minimum yang dibutuhkan tugas. Semua fitur kompleks harus menjaga jalur dasar tetap offline, tanpa daemon permanen, tanpa model lokal, dan hemat ruang.

Prinsip implementasi:

1. **Source before summary:** simpan referensi sumber atau status `unverified`; jangan membuat klaim agent otomatis berstatus benar.
2. **Context on demand:** jangan menyisipkan seluruh memori, kirim fakta penting dan pointer untuk detail.
3. **Failure is visible:** data tidak tersedia, konflik, atau kedaluwarsa harus diberi sinyal eksplisit, bukan ditutupi.
4. **Single logical writer:** transaksi diserialisasi secara aman ketika ada banyak agent, meskipun setiap agent memiliki proses stdio sendiri.
5. **Private by default:** hanya proyek terotorisasi, tidak otomatis mengangkat kode pengguna menjadi global memory.
6. **Storage is user-owned:** backup, ekspor, migrasi path, dan penghapusan tanpa lock-in.

### 22.2 Golden workflow: Codex → Claude → Gemini

**Kondisi:** pengguna sedang memperbaiki fitur di satu repository, lalu berpindah agent.

1. Codex menyelesaikan bagian pertama; skill handoff meminta `memory_checkpoint` dengan commit/branch, file yang berubah, tes lulus/gagal, keputusan, unresolved issues, dan next actions.
2. OmniMemo melakukan secret scan, memvalidasi repo root + current Git HEAD, memastikan ukuran setiap field terbatas, serta menyimpan checkpoint dengan revision, scope, provenance, dan idempotency key.
3. Claude memulai pekerjaan pada repo yang sama. Skill recall memanggil `memory_context(task, project, max_tokens=400)`; router mengambil checkpoint aktif, 3–5 decisions relevan, dan blocker, serta memberi provenance ringkas.
4. Claude dapat membuka detail keputusan melalui `memory_get(id)`, tanpa membaca keseluruhan history Codex.
5. Jika HEAD berubah dan sumber memori relevan sudah tidak cocok, OmniMemo menandai `stale` dan meminta verifikasi kode; tidak mengeksekusi instruksi dari isi memori.
6. Gemini melanjutkan setelah checkpoint baru; bila ditemukan dua keputusan bertentangan, OmniMemo menampilkan konflik, bukan memilih jawaban berdasarkan agent terakhir.

**Invariant:** perpindahan agent tidak membutuhkan riwayat privat penyedia lain; yang berpindah hanyalah memori yang disimpan eksplisit atau melalui integrasi yang diizinkan.

### 22.3 P-01 — Agent fragmentation: Universal Handoff Envelope

Gunakan format internal stabil, bukan pesan bebas:

```json
{
  "schema_version": 1,
  "project_id": "repo-fingerprint",
  "branch": "feature-x",
  "agent": "codex",
  "kind": "checkpoint",
  "goal": "Selesaikan plugin startup optimization",
  "completed": ["Test parsing konfigurasi lulus"],
  "pending": ["Ukur performa startup"],
  "blocked_by": [],
  "files_changed": ["src/main/..."],
  "git_head": "<commit-sha>",
  "tests": [{"name": "unit", "status": "passed"}],
  "timestamp": "ISO-8601",
  "privacy": "project"
}
```

**Desain:** adapter vendor menerjemahkan informasi menjadi envelope, core tidak menyimpan asumsi vendor-specific. Checkpoint masuk FTS5 tetapi tidak otomatis dipromosikan menjadi fakta permanen. Skill/hook hanya memberi _opportunity to save_; jika agent tidak menjalankan skill, manusia masih bisa menjalankan `omnimem checkpoint` atau `omnimem memory save`.

**Acceptance:** memori tertulis oleh satu agent dapat dibaca agent berbeda setelah proses penulis berhenti dan tetap valid setelah reboot.

### 22.4 P-02 — Hallucinated memory: Evidence-Based Memory / Memory Proof

Setiap memori memperoleh metadata:

```text
id, project_id, subject, predicate, value, kind,
source_type, source_uri, source_revision, source_hash,
observed_at, verified_at, validity_state,
created_by_agent, confirmation_level, sensitivity, revision
```

Jenis evidence:

- `file_snapshot`: path kanonik dalam root terotorisasi + hash isi/segmen yang diperiksa.
- `git_commit`: commit identifier + branch atau worktree context.
- `test_result`: metadata hasil pengujian, bukan klaim tes sukses yang tidak diverifikasi.
- `user_confirmed`: keputusan pengguna yang memang dikonfirmasi secara eksplisit.
- `agent_claim`: pernyataan agent tanpa bukti independen, default `unverified`.

**Aturan kritis:** angka `confidence` yang ditulis agent **bukan** bukti objektif. Validasi deterministic hanya dapat memastikan hash/path/commit benar-benar cocok, bukan otomatis membuktikan interpretasi semantik agent.

**Retrieval:** memori `unverified` boleh muncul dengan label jelas jika relevan; memori `stale`/`disputed` tidak boleh menjadi instruksi pasti. Memori berisiko tinggi perlu konfirmasi pengguna atau pemeriksaan sumber terkini.

### 22.5 P-03 — Conflicting memories: Revision Ledger & Conflict Queue

Konflik dinilai hanya antara assertion yang mempunyai `project_id + scope + subject + predicate` sebanding; tidak boleh secara keliru menyatukan fakta untuk dua branch.

**Strategi:**

1. Bentuk normalized fact key (contoh `jdk.target`) dan lihat applicable scope.
2. Jika nilai sama dan provenance cocok: deduplicate, update `last_seen`.
3. Jika nilai berbeda tetapi branch/versi berbeda: simpan keduanya sebagai scoped variants.
4. Jika nilai berbeda pada scope sama: buat `conflict_record`; jangan overwrite otomatis.
5. Beri label sumber terbaru dan tingkat otoritas, tetapi tidak memutuskan dari timestamp saja.
6. Resolusi pengguna atau verifikasi repository menambah event `supersede`, menyimpan jejak revision lama.

**Contoh:** Agen A berkata JDK 21; Agen B berkata JDK 25. Jika `gradle.properties`/toolchain mendukung JDK 25 di branch aktif, tunjukkan keputusan dengan bukti. Jika keduanya hanya klaim agent, tampilkan `disputed` dan minta pemeriksaan konfigurasi.

**CLI:** `omnimem conflicts`, `omnimem conflicts resolve <id> --source ...`.

### 22.6 P-04 — Stale memory: Git-Aware Validation

Simpan dependency fingerprint untuk setiap assertion yang berasal dari kode: file path, content hash, commit ancestor context (jika ada), serta project/branch.

- Saat query: lakukan fast-path cek project ID + branch + metadata, lalu hash check hanya pada kandidat relevan, bukan seluruh repo.
- Jika sumber hilang/berubah: status `needs_verification`/`stale`, bukan delete.
- Saat penambahan revision: buat pengganti terverifikasi, pertahankan event historis.
- Untuk memori lintas-branch: batasi scope dan ungkap bahwa sumber berasal dari branch lain.
- Untuk memori non-kode: aturan TTL spesifik; preferensi pengguna tidak kadaluarsa hanya karena commit berganti.

**Acceptance:** mengganti isi file sumber menghasilkan warning sebelum memori dipakai sebagai dasar perubahan kode.

### 22.7 P-05 — Token cost: Context Budget Broker

Pipeline deterministik:

```text
request(task, project, branch, max_tokens)
  -> authorize scope
  -> keyword/FTS5 candidate retrieval (bounded)
  -> filter outdated, duplicates, privacy, branch relevance
  -> rank by lexical match + evidence + task relevance + recency
  -> select checkpoints + decisions + blockers + file pointers
  -> tokenize with provider-aware estimator
  -> fit strict budget including metadata, source refs, tool envelope
  -> emit concise structured context + expand-on-demand IDs
```

**Tiga level:**

| Level | Anggaran | Isi yang disarankan |
|---|---:|---|
| Tiny | 150 token | 1 checkpoint + 1 next action + refs |
| Balanced | 500 token | checkpoint + top decisions + blockers + refs |
| Deep | 1.500 token | scoped graph neighborhood + evidence ringkas |

Nilai tersebut adalah default awal yang bisa diubah, bukan batas yang dipaksakan vendor. Jika budget terlalu rendah, prioritaskan status, next action, dan referensi untuk expansion. **Jangan otomatis menambahkan sumber mentah.** Karena tokenizers host bervariasi, gunakan safe margin dan exact counting ketika tokenizer yang cocok tersedia. Tool declarations, activation skill, dan seluruh round-trips harus dihitung dalam total benchmark.

**Metrics:** median total tokens per successful task, success rate, recall@k, bad-context incident rate, average MCP tool calls, p95 latency; jangan optimalkan token dengan mengorbankan kualitas.

### 22.8 P-06 — Parallel writes: SQLite Transaction Coordination (Broker hanya bila dibutuhkan)

Permasalahan: klien MCP `stdio` dapat meluncurkan beberapa proses server. `Memory Broker` bukan berarti seluruh proses otomatis mengirim ke satu objek memori di RAM. Harus ada mekanisme koordinasi antarpengguna/proses yang benar.

**MVP:** SQLite mengelola locking transaksi; `BEGIN IMMEDIATE`, `busy_timeout`, idempotency keys, retry dengan bounded backoff. Semua writers diarahkan ke lokasi database kanonik. Satu transaksi tulis aktif pada satu waktu, reads dapat berjalan saat WAL digunakan pada filesystem lokal yang memenuhi syarat.

**Tahap lanjutan:** broker IPC on-demand melalui Unix domain socket / Windows named pipe jika benchmark menunjukkan kontensi signifikan. Broker boleh otomatis berhenti ketika idle agar tidak melanggar tujuan zero-resident-daemon. Jangan langsung menggunakan daemon permanen, Redis, atau message queue eksternal.

**Recovery:** journal checkpoint + consistency check setelah crash, migration transaction, dan bounded retry. Test dengan 4–8 proses dan fault injection.

### 22.9 P-07 — External SSD: Storage Anchor & Safe Relocation

**Stable pointer:** setiap agent memanggil binary `omnimem mcp serve --stdio`; hanya konfigurasi kecil untuk menemukan data root yang berada pada lokasi user-level standar. Dengan begitu, lokasi di SSD dapat berubah tanpa mengedit ulang empat file MCP config.

**Relocation sequence:**

```text
validate target filesystem + free space
-> temporarily reject writes
-> close/checkpoint active DB connections
-> copy into temporary staging folder
-> checksum + SQLite integrity_check + index validation
-> atomic-ish switch of stable pointer only after success
-> reopen and verify read/write
-> preserve old location until explicit cleanup
-> rollback pointer on failure
```

**Disk ejection:** bila volume tidak tersedia, return explicit `storage_unavailable` (no shadow DB, no accidental empty memory creation). Jika ejection terjadi saat write, gunakan SQLite recovery pada mount kembali dan audit checkpoint terakhir. Jangan menjanjikan data selalu aman dari cabut paksa/kerusakan media.

**Filesystem policy:** APFS/macOS, NTFS/Windows, ext4/Linux sebagai recommended tested targets; exFAT dan network volumes perlu peringatan atau read-only/unsupported policy setelah pengujian. WAL tidak untuk penggunaan database bersama lewat network filesystem. Sediakan `omnimem doctor --storage`.

**Storage quota distinction:** `cache.max_size = 32MiB` hanya untuk cache sementara, tidak membatasi akumulasi database, backups, indexes, dan model embedding. Tampilkan masing-masing ukuran agar pengguna mengetahui biaya disk sebenarnya.

### 22.10 P-08 — Growth and duplicates: Memory Compactor

**Kebijakan lifecycle berbeda per jenis:**

- Facts kode: verifikasi saat sumber berubah; jika usang pindahkan ke archive dengan tombstone.
- Decisions: dipertahankan sampai dibatalkan/ditimpa secara eksplisit.
- Checkpoints: simpan hanya sejumlah N terbaru per project/branch, checkpoint lama dapat dipadatkan setelah persetujuan policy.
- Temporary observations: TTL dan retention limit pendek.
- User preferences: tidak dihapus otomatis hanya karena usia.

Compactor melakukan **deduplication by fingerprint**, merge hanya jika klaim dan scope benar-benar sama, dan _summary-of-summary_ tidak dianggap menggantikan bukti asli. Berikan dry-run sebelum destructive cleanup: `omnimem compact --dry-run`; archive/revisions tetap dapat diekspor atau dihapus sesuai retensi pengguna.

### 22.11 P-09 — Agent variance: Capability Negotiation

Adapter menguji tiap host berdasarkan kemampuan yang benar-benar tersedia: MCP config, Skill discovery, lifecycle hook, project instructions, izin proses eksternal.

- Integrasi inti: satu MCP server `stdio` dan skill lintas-platform.
- Hooks otomatis: opt-in, hanya pada host/versi yang mendukung; jangan memalsukan kompatibilitas.
- Bila host tidak memanggil skill: dokumentasikan perintah manual dan `omnimem context` CLI, serta berikan instruksi bootstrap yang singkat jika pengguna menyetujuinya.
- Installer menghitung diff, meminta persetujuan, menyimpan backup, serta mendukung clean uninstall.
- Capability matrix harus terikat versi; gunakan contract tests di CI daripada hardcode key konfigurasi lintas vendor.

**Catatan protokol:** MCP clients tidak selalu mendukung fitur versi terbaru secara serempak. Implementasikan negotiation dan fallback sesuai host; jangan mengasumsikan setiap klien memahami konsep session/transport yang sama.

### 22.12 P-10 — Scope leaks and prompt injection: Memory Firewall

- Server menentukan project ID dari authorized canonical root, bukan hanya `project_id` yang dimasukkan agent dalam argumen.
- Scope `global` hanya untuk preferensi generik yang disetujui pengguna. Source code, tickets, dan konfigurasi produk tidak otomatis global.
- Terapkan permission read/write sesuai project dan sensitivity, dengan deny-by-default untuk cross-project.
- Retrieved memory berisi _data_, tidak memiliki otoritas mengubah instruksi sistem, menjalankan shell, atau mengirim data ke jaringan.
- Secret scanner menolak/meredaksi high-risk data. Pengguna dapat mengatur denylist path seperti `.env`, SSH keys, credential files.
- HTTP bersifat opsional dan non-default; jika dinyalakan, bind loopback, authentication, Origin validation, rate limits, dan explicit authorization.
- Disk encryption adalah opsi tersendiri atau bergantung pada filesystem encryption; SQLite default bukan encrypted storage.

### 22.13 Data Flow & Repository Design Amendments

Tambahan struktur modular:

```text
crates/
  omnimem-core/src/context_budget.rs
  omnimem-core/src/validation.rs
  omnimem-core/src/conflicts.rs
  omnimem-storage/src/relocation.rs
  omnimem-storage/src/write_coordination.rs
  omnimem-storage/src/compaction.rs
  omnimem-adapters/src/capabilities.rs
  omnimem-security/src/scope_guard.rs
```

Tabel tambahan:

- `memory_assertions` — structured facts dengan scope, validity, evidence refs.
- `memory_events` — append-only create/update/supersede/review/delete audit metadata.
- `memory_evidence` — source type/path/hash/commit/test references.
- `memory_conflicts` — asserted key, competing memory IDs, resolution event.
- `memory_checkpoints` — structured handoff envelope.
- `storage_roots` — stable pointer history, generation, validation state.
- `retrieval_receipts` — opt-in metrics tanpa menyimpan raw private prompt.

**Indexes:** `(project_id, branch, subject, predicate)` dan `(status, updated_at)`; FTS5 untuk teks, foreign keys ON, uniqueness key untuk idempotent writes.

### 22.14 New MCP/CLI surface — minimal by default

Jangan menambah semua tools ke discovery default. Masukkan mekanisme guardian ke enam core tools tanpa schema bloat; expose administrasi lewat CLI:

```text
omnimem doctor --storage
omnimem doctor --agents
omnimem conflicts list
omnimem conflicts resolve <id>
omnimem memory verify <id>
omnimem memory explain <id>
omnimem compact --dry-run
omnimem relocate <target> --verify
omnimem metrics --token-roi
```

Jika memerlukan fungsi MCP lanjutan, buat capability-flag opt-in, bukan menambah puluhan tools ke setiap agent context.

### 22.15 Launch gates and failure-mode tests

| ID | Skenario | Hasil wajib |
|---|---|---|
| G-01 | Agent menulis fakta tanpa bukti | Muncul sebagai `unverified`, tidak ditampilkan authoritative |
| G-02 | Dua agent memberi nilai bertentangan pada scope sama | Konflik dicatat, tidak overwrite diam-diam |
| G-03 | File bukti berubah setelah checkpoint | Hasil berikutnya berlabel stale/needs-verification |
| G-04 | Agent melewati scope authorized root | Server menolak tanpa mengekspos data |
| G-05 | 8 writer concurrent mengirim revision sama | Idempotent, data konsisten, integrity check lulus |
| G-06 | SSD terlepas setelah MCP sudah berjalan | Explicit error, no fallback shadow DB |
| G-07 | Relocation gagal sebelum pointer switch | DB lama tetap valid dan digunakan |
| G-08 | Cache penuh 32 MiB | LRU eviction, persistent records utuh |
| G-09 | User hanya meminta bug fix sederhana | Context minimal; alat tidak membanjiri dengan sejarah proyek |
| G-10 | Agent memanggil memory dengan prompt injection tersimpan | Data ditampilkan sebagai untrusted evidence, bukan perintah |
| G-11 | Installer jalan dua kali | Tidak ada duplikasi skill/config |
| G-12 | Memory system mati | Coding agent tetap dapat bekerja tanpa memori; kesalahan jelas terlihat |

### 22.16 MVP implementation order

**MVP-1: vertical slice lintas-agent**

1. Rust binary + SQLite migrations + project fingerprint.
2. `memory_save`/`memory_context`/`memory_get`/`memory_checkpoint` via MCP stdio.
3. FTS5 lexical retrieval + bounded context envelope.
4. Dua skill (`recall`, `handoff`) dan dua host adapter terlebih dahulu.
5. Test handoff benar-benar berganti provider/agent.

**MVP-2: trust + reliability**

6. Evidence flags, scoped ACL, secret filter, branch validation.
7. Atomic writes, concurrency stress tests, conflict queue.
8. Relocation engine, unplug safety, backup/recovery, doctor.
9. Empat agent adapters dengan golden compatibility tests.

**MVP-3: optimization**

10. Compaction, adaptive budgets, graph neighborhood, opt-in hooks.
11. Full token ROI benchmark melawan baseline no-memory/static-brief.
12. Release packaging, reproducible build, documentation.

**Not MVP:** model embedding mandatory, auto-index seluruh workspace, raw chat capture, cloud sync, always-on server, public HTTP binding, automatic cross-project memories.

### 22.17 Key design decision

**Prioritaskan 'memory correctness per token', bukan sekadar jumlah memori atau banyaknya tool MCP.** Produk berhasil jika agent berikutnya memahami tugas dengan cepat dan benar, dan kegagalan memori terlihat jelas. Kecepatan, ukuran kecil, dan portabilitas adalah konsekuensi arsitektur yang disiplin, bukan alasan untuk melemahkan verifikasi.

## 23. Reference notes for v1.1 (masih berlaku pada v1.2)

- Agent Skills standard, progressive disclosure: https://agentskills.io/specification
- MCP transport and versioning: https://modelcontextprotocol.io/specification
- SQLite WAL and caveats: https://www.sqlite.org/wal.html
- SQLite filesystem locking caveats: https://www.sqlite.org/useovernet.html


---

## 24. Amendment v1.2 — Anti-Overengineering Engineering Policy (WAJIB)

### 24.1 Design thesis

OmniMemo harus **kecil karena disiplin arsitektur**, bukan karena mengorbankan keandalan. Terapkan YAGNI, KISS, dan perubahan minimum yang dapat diuji. Aturan ini berlaku untuk **semua agent dan kontributor**, termasuk saat agent menulis source code, refactor, membuat dokumentasi, mengubah dependensi, menyimpan memori, atau mengusulkan roadmap.

**Definition:** Overengineering berarti menambah abstraksi, dependensi, layanan, framework, mekanisme, dan konfigurasi yang tidak dibutuhkan untuk memecahkan kasus penggunaan yang terverifikasi, atau yang manfaatnya lebih kecil daripada biaya maintenance. Security, correctness, recovery, dan test yang relevan **tidak** boleh dihapus atas nama kesederhanaan.

### 24.2 Aturan normatif AG-01 s.d. AG-16

| ID | Aturan | Syarat pemenuhan |
|---|---|---|
| AG-01 | **Build the smallest working vertical slice first.** | Selesaikan alur simpan → ambil → handoff pada 2 agent sebelum fitur lanjutan. |
| AG-02 | **No speculative features.** | Fitur harus punya use case, pemilik keputusan, acceptance test, dan manfaat terukur. |
| AG-03 | **No premature abstraction.** | Jangan buat generic framework, adapter hierarchy, trait berlapis, atau plugin system untuk satu implementasi. |
| AG-04 | **Prefer standard capabilities.** | Gunakan SQLite/FTS5, transaksi, dan pustaka yang sudah ada sebelum memperkenalkan layanan lain. |
| AG-05 | **No mandatory background services.** | Tidak ada Redis, Neo4j, Docker, Kubernetes, message broker, cloud service, always-on daemon untuk MVP. |
| AG-06 | **No dependency without justification.** | Dependensi baru wajib memiliki use case, alternatif, estimasi footprint, lisensi, dan security review proporsional. |
| AG-07 | **Stay within scope.** | Jangan refactor file di luar kebutuhan tanpa bukti dampak fungsional yang langsung terkait. |
| AG-08 | **Readable beats clever.** | Utamakan kode eksplisit, predictable error handling, dan dokumentasi minimal yang berguna. |
| AG-09 | **Do not optimize without benchmark.** | Tulis baseline dan metrik sebelum mengklaim optimasi memory, latency, token, atau disk. |
| AG-10 | **No duplicate source of truth.** | Satu core config; jangan gandakan DB, per-agent memo store, atau policy. |
| AG-11 | **Fail safely; avoid silent fallback.** | Storage offline tidak boleh membuat DB bayangan; error harus jelas dan recoverable. |
| AG-12 | **Make destructive actions explicit.** | Relocate, purge, migration irreversible, forced update memerlukan konfirmasi/backup yang sesuai. |
| AG-13 | **Preserve external user state.** | Installer harus idempotent, menyimpan backup, dan tidak mengganti Git config/hooks agent tanpa persetujuan. |
| AG-14 | **Tests proportional to risk.** | Uji API contract, migrasi, race condition, scope, dan recovery; hindari mock berlebihan. |
| AG-15 | **Stop when acceptance criteria pass.** | Jangan menambah fitur saat tugas semula sudah selesai kecuali diminta. |
| AG-16 | **No autonomous push or credential handling.** | Memori dan agent tidak boleh menyimpan token GitHub, mengubah akun, atau melakukan push tanpa izin eksplisit. |

### 24.3 Default implementation decisions (MVP)

**Wajib:** satu binary Rust, SQLite + FTS5, empat operasi inti MCP (save/get/context/checkpoint), konfigurasi datar sederhana, dua host adapter pertama, repository-scoped memory, CLI inspeksi, per-write provenance. Gunakan library MCP yang relevan hanya jika mengurangi risiko dan footprint secara masuk akal.

**Tunda:** vector embedding, model LLM internal, semantic clustering, graph visualization UI, sync antar-device, multi-user accounts, plugin marketplace, HTTP server, dashboard web, telemetry cloud, background scheduler, distributed broker.

**Hanya jika ditemukan bottleneck:** IPC broker, worker pool, batched reindexer, ANN/vector database, filesystem watcher. Hasil benchmark wajib menyebut baseline, repro steps, skala dataset, nilai yang ditarget, hasil, dan tradeoff.

Jangan mengartikan target 'RAM idle <60 MiB' atau 'cache 32 MiB' sebagai alasan untuk menolak fitur reliability yang diperlukan. Angka itu target uji, bukan veto mutlak.

### 24.4 Change budget & decision gate

Sebelum coding, agent wajib menjawab ringkas secara internal atau dalam change summary:

1. Apa permintaan pengguna dan acceptance test-nya?
2. Solusi paling sederhana yang memenuhi requirement?
3. Apakah ada modul atau pola yang sudah tersedia?
4. Apakah ada dependensi, abstraksi, atau file baru? Jika ya, kenapa tidak dapat dihindari?
5. Risiko correctness, security, compatibility, dan rollback?
6. Bagaimana memverifikasi perubahan tanpa menambah pekerjaan tidak relevan?

**Pilihan default:** (a) ubah implementasi yang sudah ada; (b) tambah helper sederhana saat perlu; (c) baru buat modul bila ada tanggung jawab terpisah yang teruji; (d) arsitektur baru memerlukan persetujuan pengguna atau ADR (Architecture Decision Record) singkat.

**Reject examples:** membuat microservice baru untuk cache 32 MiB; membuat abstraction registry untuk satu SQLite driver; memaksa cloud embeddings agar memori searchable; menambahkan UI sebelum MCP berhasil; refactor seluruh crate demi menambah satu error case.

### 24.5 PR review checklist

- [ ] Perubahan menjawab satu masalah terverifikasi dan tidak melebihi scope.
- [ ] Tidak ada layanan baru tanpa kebutuhan/bukti.
- [ ] Tidak ada dependency baru tanpa alasan.
- [ ] Code path sederhana, tidak ada abstraction for future needs.
- [ ] Error/failure path, tests, dan rollback proporsional.
- [ ] Benchmarks untuk klaim performa/hemat token.
- [ ] Identity lock, privacy, dan storage constraints tetap berlaku.

### 24.6 Metrics for anti-overengineering

Ukur total dependency/runtime footprint, jumlah binary/daemon wajib, jumlah MCP tools exposed default, cold start, RAM idle, disk cache (bukan database), latency p95 retrieval, median full-task token cost, jumlah konfigurasi yang harus diubah setelah pindah SSD, serta regression rate. Target diterima jika kualitas tugas tidak menurun material.

## 25. Amendment v1.2 — GitHub Identity Lock & Push Governance (WAJIB)

### 25.1 Single authorized GitHub owner

**Approved GitHub username:** `YanIanZ`. Tidak ada identitas agent, bot, layanan pihak ketiga, atau nama pembuat otomatis sebagai author/committer tanpa perubahan kebijakan yang disetujui pemilik proyek.

Tiga identitas berbeda yang harus dipahami:

1. **Commit author/committer** berasal dari metadata Git (nama/email) dan dapat dipalsukan lewat local config/env; memastikan format bukan bukti otentikasi.
2. **GitHub pushing account** ditentukan SSH key atau token yang digunakan saat push; tidak otomatis sama dengan `git config user.name`.
3. **Destination repository** ditentukan effective push URL, dan dapat berbeda dari fetch URL atau akun GitHub CLI yang sedang aktif.

**Tujuan:** semua commit baru yang dibuat agent untuk proyek ini memakai `YanIanZ` dan email terverifikasi yang **disediakan langsung oleh pemilik**, seluruh push yang diizinkan memakai akun GitHub YanIanZ menuju repository `github.com/YanIanZ/<repo>`, tanpa push otomatis.

### 25.2 Normative rules GH-01 s.d. GH-16

| ID | Rule | Behavior |
|---|---|---|
| GH-01 | Authorized identity only | `author.name` dan `committer.name` untuk commit baru harus `YanIanZ`. |
| GH-02 | Verified email only | Gunakan satu email verified/noreply milik YanIanZ; tidak boleh menebak alamat noreply. |
| GH-03 | No AI attribution | Tidak membuat `Co-authored-by` agent atau footer generator AI otomatis. |
| GH-04 | No fake contributors | Jangan membuat atribusi orang/bot lain yang tidak benar. |
| GH-05 | Local explicit config | Set `user.name`, `user.email`, `user.useConfigOnly=true` di repo setelah persetujuan. |
| GH-06 | Check effective identity | Periksa `git var GIT_AUTHOR_IDENT` dan `git var GIT_COMMITTER_IDENT`, termasuk env overrides. |
| GH-07 | Only approved owner repo | Push hanya ke effective `origin` push URL `github.com/YanIanZ/<repo>` yang di-allowlist. |
| GH-08 | Check push authentication | Untuk SSH, probe akun SSH yang benar; untuk HTTPS gunakan helper terverifikasi. `gh api user` saja bukan bukti akun Git push. |
| GH-09 | Ask before each push | Perubahan remote dan aktivitas jaringan tulis tidak boleh otomatis; minta user approval untuk push. |
| GH-10 | Deny dangerous Git actions | Force-push, delete branch/tag, `--mirror`, branch rewrite, dan amend published commits ditolak secara default. |
| GH-11 | No agent credential storage | Jangan menaruh token, PAT, SSH private key, cookies dalam OmniMemo, logs, prompt, atau Git. |
| GH-12 | No silent Git mutations | Tidak mengubah `remote`, `credential.helper`, `core.sshCommand`, `core.hooksPath`, GitHub auth, atau signing key tanpa izin. |
| GH-13 | No automatic remote creation | Tidak membuat repo di akun lain atau fork tanpa permintaan. |
| GH-14 | Verify proposed commits | Sebelum push inspeksi range commits baru, author, committer, trailers, diff, branch, dan dirty state bila relevan. |
| GH-15 | Treat guard failures as stop | Jika identity/auth/remote tidak terverifikasi, **jangan push**; tampilkan alasan dan langkah remediasi. |
| GH-16 | Protect on server too | GitHub permissions, protected branch/ruleset, signed commits bila sesuai paket/opsi, dan review adalah kontrol yang lebih kuat. |

**Ketentuan kolaborasi:** bila proyek kelak menerima kontribusi pihak ketiga, jangan menulis ulang kepengarangan yang sah untuk mengklaimnya atas nama YanIanZ. Default lock ini dimaksudkan untuk commit **baru yang dibuat agent atas permintaan pemilik**. Imported commits dan PR orang lain membutuhkan pengecualian terotorisasi, bukan pemalsuan metadata.

### 25.3 Recommended setup (per-repository; tidak dijalankan otomatis)

Pengguna memilih email yang terverifikasi dalam GitHub Settings > Emails, misalnya bentuk `ID+YanIanZ@users.noreply.github.com` **hanya jika memang tercantum di akun**.

```bash
# Jalankan setelah mengisi alamat yang benar; JANGAN masukkan email tebakan.
git config --local user.name 'YanIanZ'
git config --local user.email '<VERIFIED_GITHUB_EMAIL>'
git config --local user.useConfigOnly true

# Cek metadata yang benar-benar akan digunakan Git:
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT

# Verifikasi tujuan efektif, termasuk pushurl jika ada:
git remote get-url --push origin

# Cek akun aktif untuk GitHub CLI (diagnosis, belum memastikan SSH Git):
gh auth status --active --hostname github.com
gh api user --jq .login

# Jika menggunakan SSH, verifikasi identitas key SSH GitHub:
ssh -T git@github.com
```

**Peringatan:** untuk akun SSH, pesan GitHub 'Hi YanIanZ!' adalah indikator akun yang menerima key; `ssh -T` pada autentikasi yang berhasil biasanya mengembalikan exit code nonzero karena tidak tersedia shell. Pastikan `GIT_SSH_COMMAND`, `core.sshCommand`, maupun rewrite URL tidak memakai jalur autentikasi lain. Untuk HTTPS, Git Credential Manager/credential helper harus diikat dan diperiksa sesuai akun yang benar. Perlindungan sepenuhnya terhadap klien yang sengaja melewati hook memerlukan pembatasan akses server-side.

### 25.4 Enforcement layers

**L1 — Agent policy (AGENTS.md):** stop ketika push belum diotorisasi; tidak membuat commit dengan metadata agent. Wajib terpasang dan dibaca host terkait.

**L2 — Local Git validation (optional Git hooks):** `pre-commit` memvalidasi author/committer dan email; `pre-push` memvalidasi remote/effective account/new commit metadata, menolak delete/non-FF, serta memerlukan approval. Hook tidak otomatis aktif dari isi repository: user menginstal sendiri setelah memeriksa hook yang sudah ada. Git hooks bisa dilewati dengan opsi seperti `--no-verify` atau konfigurasi lain.

**L3 — GitHub server controls:** akses tulis repo dibatasi oleh otorisasi GitHub. Untuk protected branches, gunakan branch protection/rulesets dengan limit plan/platform yang berlaku; metadata format restrictions atau signed commits hanya jika fitur tersedia. CI checks dapat mendeteksi anomali, tetapi tidak sama dengan pre-receive authorization. Untuk personal repo tidak bisa menganggap semua aturan organisasi/enterprise tersedia.

**L4 — Credential security:** SSH keys/token hanya milik pengguna dan tidak disalin ke project, agent memory, atau disk backup yang tidak aman.

### 25.5 Proposed CLI support (post-MVP)

```text
omnimem git identity status
omnimem git guard inspect --repo .
omnimem git guard install --dry-run
omnimem git guard install --require-approval
omnimem git guard uninstall --keep-existing-hooks
```

Perintah di atas adalah **target desain, bukan fitur CLI yang sudah tersedia**. Sebelum menambahkan subcommand ini, ukur apakah cukup memakai Git config/hook tanpa code Rust tambahan (aturan anti-overengineering).

### 25.6 User approval and audit

- Before push: tampilkan akun target, URL remote, branch, commit list/range, diff summary, dan risiko.
- Agent tidak boleh menyimpulkan izin push hanya karena user sebelumnya memberikan izin untuk commit.
- Semua kegagalan identity lock dilaporkan; jangan bypass atau edit user metadata diam-diam.
- Audit log lokal (jika diaktifkan) menyimpan outcome dan metadata nonrahasia; jangan merekam token.
- Jika user meminta kontribusi ke repo milik organisasi/teman, policy harus diubah melalui persetujuan eksplisit, bukan menebak pengecualian.

## 26. Amendment v1.2 — Extended Acceptance Tests / Launch Gates

| Test ID | Skenario | Expected |
|---|---|---|
| AO-01 | Agent diminta menambah cache kecil | Tidak membuat Redis/daemon baru tanpa benchmark kebutuhan |
| AO-02 | Pencarian FTS5 memenuhi standar recall | Embedding dan vector store tetap nonaktif |
| AO-03 | Perubahan bug satu modul | Tidak refactor semua crate tanpa alasan |
| AO-04 | Usulan dependency | Ada alternatif, justifikasi manfaat/footprint, dan acceptance |
| AO-05 | Iterasi setelah acceptance terpenuhi | Agent berhenti dan memberikan summary, tidak membangun fitur tambahan |
| GH-T01 | Git author/committer bukan YanIanZ | Commit baru ditolak oleh guard |
| GH-T02 | Email salah/bukan yang disetujui | Commit dan push ditolak oleh guard |
| GH-T03 | Push URL menuju akun lain | Push ditolak sebelum koneksi tulis |
| GH-T04 | SSH identity berbeda | Push ditolak ketika identity dapat diverifikasi berbeda |
| GH-T05 | `gh` login lain tetapi SSH key benar | Diagnosa menunjukkan perbedaan dan kebijakan fail-closed memilih stop |
| GH-T06 | Metadata commit memiliki AI coauthor | Reject sesuai policy no-AI-attribution |
| GH-T07 | Push tanpa explicit approval | Agent tidak menjalankan push |
| GH-T08 | `--force`, branch deletion, atau remote rewrite | Ditolak kecuali exception melalui perubahan kebijakan |
| GH-T09 | `git push --no-verify` | Dinyatakan di docs sebagai bypass hook lokal; mitigasi permissions/ruleset server |
| GH-T10 | Repo kolaboratif punya commit pihak lain | Tidak memalsukan author historis; meminta exception/review |

**Release condition:** core memory tetap sederhana, security dan correctness utuh, dan tidak ada identitas AI yang diterbitkan sebagai penulis commit atas nama pemilik. Kiriman ke GitHub harus memakai credential yang sesuai dan membutuhkan otorisasi pengguna.

### 26.1 Source of truth & agent distribution

`AGENTS.md` di root repository adalah **canonical** untuk policy engineering dan GitHub identity. `CLAUDE.md` dan `GEMINI.md` adalah shim singkat agar host membaca AGENTS.md. OpenCode/Codex mengikuti mekanisme instruksi yang didukung versinya; jangan mengasumsikan semua host membaca file sama tanpa uji. Jika ada aturan agent global, policy project yang lebih ketat berlaku sepanjang tidak bertentangan dengan system/developer policy platform.

### 26.2 Sources

- Git configuration identity and `user.useConfigOnly`: https://git-scm.com/docs/git-config
- Git hooks (`pre-commit`, `pre-push`, `--no-verify`): https://git-scm.com/docs/githooks
- GitHub commit email attribution: https://docs.github.com/en/account-and-profile/concepts/email-addresses
- GitHub rulesets and availability: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- GitHub CLI active account: https://cli.github.com/manual/gh_auth_status

---

# Amendment v1.3 — OmniMemo Mission Control & Universal Multi-Agent Office

**Status:** Proposed — technical product requirements, not implemented.  
**Inspirasi:** [Hikayat Developer — “I Created a Real-Time AI Agent Office (100% Local) | Claude AI + Mission Control UI”](https://www.youtube.com/watch?v=UPUPoGsa_3M), dipublikasikan pada 6 Juni 2026. Deskripsi publik video menyebut Project Manager, Software Engineer, UI/UX Designer, QA Tester, Product Owner, live task tracking, mission-control dashboard, office-style visualization, dan multi-agent collaboration. Tidak diasumsikan bahwa seluruh detail internal/protokol video tersedia atau terverifikasi.  
**Prinsip integrasi:** Tambahkan kemampuan koordinasi dan visualisasi TANPA mengubah OmniMemo menjadi framework swarm yang berat. Semua aturan Memory Guardian, Anti-Overengineering (bagian 24), dan GitHub Identity Lock (bagian 25) tetap **mengikat**.

## 27. Vision, Boundaries, and Release Strategy

**Feature name:** OmniMemo Mission Control (OMC). Memungkinkan pengguna mengamati, mengarahkan, dan mengoordinasikan beberapa AI coding agent dalam **satu workspace lokal**, sambil berbagi memori, keputusan, progres, bukti, dan handoff antar-agent.

**Tiga mode bertingkat:**

1. **Memory-only (default):** hanya CLI + MCP + Agent Skills. Tanpa server dashboard, tanpa polling agent, tanpa proses latar permanen; cocok bagi pengguna satu atau beberapa agent yang bekerja bergantian.
2. **Observe (MVP dashboard):** dashboard lokal on-demand menampilkan agent terdaftar, heartbeat jika tersedia, task board, handoff, memori terpilih, event, dan status kegagalan. Tidak menjalankan proses agent baru.
3. **Coordinate (opt-in, post-MVP):** penugasan eksplisit, ownership, dependency, review, dan—jika adapter telah diaudit—peluncuran sesi agent yang diizinkan. Eksekusi multi-agent tidak boleh otomatis hanya karena UI dibuka.

**Tidak termasuk v1.3 MVP:** autonomous team of 20 agents, mandatory local LLM/GPU, Docker/Kubernetes, centralized cloud control plane, full chat-history scraping, 3D engine, message bus eksternal, marketplace plugin, scheduler persisten, auto-merge, auto-push.

**Penting:** “100% local” dalam spesifikasi ini berarti **penyimpanan, MCP, server UI, data tugas, dan orkestrasi dilakukan secara lokal**. Codex/Claude/Gemini/OpenCode dapat menggunakan model/provider jarak jauh sesuai pengaturan pengguna. Jangan pernah mengiklankan inference sepenuhnya offline jika menggunakan layanan model cloud.

## 28. Roles vs. Agent Runtimes

Peran adalah **label tanggung jawab**, bukan provider/model. Satu peran dapat dijalankan Codex, Claude, Gemini, atau OpenCode; satu runtime dapat mengambil beberapa peran pada waktu berbeda. Tidak ada kewajiban untuk membuat lima agent berbayar sekaligus.

| Role template | Tanggung jawab | Contoh output | Gate |
|---|---|---|---|
| Product Owner | merinci kebutuhan, acceptance criteria | task specification | pengguna menyetujui scope signifikan |
| Project Manager | membagi tugas, urutan kerja, dependensi | backlog / handoff | tidak dapat memberikan otorisasi GitHub push |
| Software Engineer | implementasi di worktree yang diizinkan | patch + tests | validasi perubahan dan identitas git |
| UI/UX Designer | user flows, aksesibilitas, UI spec | design brief / frontend changes | tidak mengubah kode backend tanpa tugas |
| QA Tester | test, risiko regresi, review independen | test report / findings | tidak boleh mengesahkan pekerjaan sendiri |
| Reviewer (opsional) | cek desain, keamanan, diff | approve/reject/rework | review bukan izin push |

Contoh assignment: `Software Engineer -> codex`, `Reviewer -> claude`, `QA -> gemini`, `UI/UX -> opencode`. Semua mapping **dapat diubah** dan tidak menjamin provider memiliki kemampuan automation/launch yang sama.

### 28.1 Capability-based adapters

Setiap adapter wajib mengiklankan kemampuan nyata (bukan hasil asumsi nama brand) berupa:

```json
{
  "agent_id": "codex-local-1",
  "provider": "codex",
  "capabilities": {
    "mcp_memory": true,
    "skills": true,
    "session_observe": "supported|unsupported|unknown",
    "session_launch": "supported|unsupported|unknown",
    "task_injection": "supported|unsupported|unknown",
    "event_stream": "supported|unsupported|unknown",
    "usage_metrics": "supported|unsupported|unknown"
  },
  "permission_profile": "read-only"
}
```

`mcp_memory`/`skills` merupakan kemampuan deklaratif yang tetap harus diuji; dukungan hooks, events, resume, launching, dan usage ditentukan lewat compatibility probes per versi host. **Tidak ada scraping file sesi privat** atau pengiriman command lewat protokol tidak resmi sebagai fallback diam-diam.

## 29. User Journey — End-to-End Collaboration

**Skenario:** Pengguna mengembangkan plugin Minecraft secara paralel, tetapi hanya ingin satu GitHub identity `YanIanZ`.

1. Pengguna memilih workspace di dashboard; OMC memuat hanya project scope yang diizinkan.
2. Buat task `T-101: Optimize plugin startup`, subtask `T-102: QA regression`, dan acceptance tests. Task secara default `todo`.
3. Pengguna memilih `Codex` sebagai Software Engineer dan `Claude Code` sebagai Reviewer. Jika adapter hanya mendukung MCP, assignment tetap dibuat, tetapi pengguna membuka sesi agent sendiri lalu agent melakukan claim lewat MCP.
4. Codex mengambil task melalui `task_claim`, membaca `memory_context` dengan token budget, melakukan perubahan pada worktree/branch yang disetujui, dan mengirim progress/event serta evidence.
5. Status berubah menjadi `in_review` hanya setelah checkpoint berisi file yang berubah, hasil test, dan referensi commit/diff yang relevan.
6. Claude membaca context + artifact, memberikan review temuan dan keputusan `approved` atau `changes_requested` sebagai hasil **review teknis saja**.
7. Pengguna menyetujui merge/commit/push secara terpisah. **OMC tidak pernah menganggap status QA/Review sebagai persetujuan GitHub push.**
8. Gemini CLI bisa mengambil task lanjutan dengan konteks T-101/T-102 tanpa membaca seluruh chat agent sebelumnya.
9. Jika SSD eksternal OmniMemo terlepas, task mutasi berhenti dengan status `storage_unavailable` (fail-closed) dan UI menampilkan recovery, tidak membuat storage baru.

## 30. UX & Mission Control Dashboard

### 30.1 Views yang wajib didukung

**Overview:** projects, agents online/idle/unknown/working/blocked, task progress, pending approvals, recent events, memory health, storage readiness.

**Task Board:** Kanban `Backlog -> Ready -> In Progress -> In Review -> Done` plus `Blocked/Cancelled` sebagai state khusus, dengan priority, dependency, assignee, role, branch/worktree, acceptance checklist.

**Agent Directory:** provider/CLI version (jika dapat dideteksi), role, permissions, observed capabilities, status evidence/last seen, per-agent task ownership. Jangan menampilkan `online` bila hanya ditemukan binary di filesystem.

**Timeline & Handoffs:** append-only high-level events (task_claimed, checkpoint_saved, test_reported, review_requested, approval_required); payload dibatasi dan secret-redacted. Pengguna dapat membuka detail bila diizinkan.

**Memory Explorer:** search, provenance, conflicting/stale flags, graph neighbors yang dibatasi, scope; tampilkan memori yang relevan dengan task—bukan seluruh database per refresh.

**Approvals & Git:** antrean tindakan sensitif, actor & target, tujuan repository, effective push URL, branch, diff/commit summary, identity status, dan pesan eksplisit bahwa approval akan berlaku **untuk aksi spesifik yang disetujui**. Tombol UI tidak boleh melewati policy runtime maupun Git hooks.

**Office View (post-MVP):** visualisasi 2D opsional yang menampilkan karakter/desk setiap role dan animasi berbasis status terverifikasi (working, reviewing, idle, blocked). Ini *visualization only*: tidak menjalankan AI. Tidak memerlukan canvas WebGL/3D/game engine untuk MVP.

### 30.2 Layout sederhana

```text
+------------------------------------------------------------------------+
| OmniMemo Mission Control   [Workspace] [Storage OK] [Memory 245]       |
+---------------+--------------------------------+-----------------------+
| Agent Fleet   | Tasks / Kanban                 | Activity / Approvals  |
|               |                                |                       |
| Codex Working | TODO  READY  DOING  REVIEW DONE| QA checkpoint          |
| Claude Review | T-4   T-8    T-2    T-1    T-0 | Claude needs review   |
| Gemini Idle   |                                | Push: approval needed |
| OpenCode ?    | [selected task + evidence]     | Memory conflict       |
+---------------+--------------------------------+-----------------------+
| [Memory] [Timeline] [Git] [Office View (optional)]                      |
+------------------------------------------------------------------------+
```

**Accessibility:** keyboard-first navigation, non-color-only status indicators, reduced-motion option, readable timestamps, narrow-screen fallback. Render ringkas; tidak memuat graph penuh secara default.

### 30.3 Real-time semantics

- Gunakan SSE (Server-Sent Events) di loopback `127.0.0.1` selama dashboard aktif. WebSocket hanya jika kebutuhan bidirectional persisten terbukti.
- Event diterbitkan hanya saat state berubah. UI **tidak** mem-poll session history besar setiap beberapa detik.
- Heartbeat hanya jika adapter resmi/hook memiliki sinyal; tanpa sinyal status `unknown` atau `not_observed`, bukan `idle`/`offline` hasil dugaan.
- Jika browser disconnect, UI reload snapshot dan sambung event dari `last_event_id`; gap ditandai eksplisit.
- Event latency target: p95 <2 detik dari pencatatan lokal ke UI pada beban normal, diukur (bukan dijamin untuk host tanpa event support).

## 31. Task Engine & Cooperative Handoffs

### 31.1 Task state machine

`backlog -> ready -> in_progress -> in_review -> done`; allowed transitions `ready|in_progress|in_review -> blocked`, `blocked -> ready`, dan `nonterminal -> cancelled`. `changes_requested` dari review kembali ke `in_progress`. `done` membutuhkan evidence acceptance; tidak mengimplikasikan merged/pushed.

Task minimal: `id`, `workspace_id`, `project_id`, `title`, `goal`, `acceptance`, `state`, `priority`, `role`, `assignee_agent_id`, `lease_owner`, `lease_expires_at`, `depend_on[]`, `branch`, `worktree`, `artifact_refs[]`, `created_at`, `updated_at`, `revision`.

### 31.2 Ownership & idempotency

- `task_claim(task_id, expected_revision)` memakai transaksi SQLite atomik dengan CAS revision. Agen kedua menerima `already_claimed` dan identitas pemilik task, bukan diam-diam mengambil alih.
- Lease mencegah dua agent mengerjakan task yang sama; expiry dapat dikonfigurasi. Lease habis **tidak otomatis membunuh proses agent**; pengguna harus melakukan review sebelum reassignment.
- `task_update` dan `task_complete` menyertakan `idempotency_key`, `expected_revision`, dan evidence. Retry tidak menciptakan checkpoint duplikat.
- `blocked` menyimpan alasan, owner, dependency, dan tindakan yang diperlukan. Handoff memuat `completed`, `files_changed`, `tests_run`, `decisions`, `blockers`, `next_actions`, serta referensi provenance.
- Satu project bisa digunakan beberapa agent asalkan scope ACL mengizinkan, tetapi **shared memory != shared filesystem write permission**.

### 31.3 Conflict minimization

Default `1 active writer per shared worktree`. Parallel editing hanya dibolehkan bila menggunakan **Git worktree/branch terpisah** atau disjoint-file ownership yang terverifikasi. Advisory lock pada tabel task/paths membantu koordinasi tetapi bukan pengganti Git concurrency control. Sebelum integrasi, review perubahan, tests, dan conflict resolution tetap wajib.

Task dependencies dapat ditangani via topological readiness check sederhana dalam SQLite/Python/Rust, **tanpa** distributed queue/scheduler eksternal.

## 32. New MCP Tools (Optional, Capability-Gated)

OmniMemo memory tools v1.2 tetap default. OMC **tidak** mengekspos seluruh schema orchestration ke setiap agent secara otomatis, demi menghindari tool-token overhead. Tool group `mission_control` dinyalakan hanya di workspace yang opt-in.

| MCP tool | Minimal fields | Authorization |
|---|---|---|
| `mc_tasks` | `workspace_id, filters, limit` | read project tasks |
| `mc_task_get` | `task_id` | read scope |
| `mc_task_claim` | `task_id, expected_revision` | role/agent permission |
| `mc_task_update` | `task_id, patch, expected_revision, idempotency_key` | task owner |
| `mc_task_handoff` | `task_id, checkpoint_id, evidence_refs[]` | task owner |
| `mc_agent_status` | `agent_id, status, evidence_kind` | registered agent/hook |
| `mc_review_submit` | `task_id, verdict, findings[]` | reviewer different from implementer |

Admin-only CLI/UI actions (bukan MCP tools agent umum) mengatur create task, assignment, launch, cancellation, approval, git guard, relocation, and permission changes. Ini memisahkan tindakan AI dari otoritas manusia.

**Example event envelope:**

```json
{
  "event_id": 83,
  "type": "task.handoff_saved",
  "workspace_id": "ws-example",
  "task_id": "T-101",
  "agent_id": "codex-local-1",
  "occurred_at": "2026-10-18T14:00:00Z",
  "summary": "Regression tests passed; ready for review",
  "evidence_refs": ["checkpoint:cp-42"],
  "safe_to_display": true
}
```

No arbitrary command execution through generic MCP tasks. For agent launching (post-MVP) use an audited allowlist of binaries and safe argument arrays; no shell interpolation, user confirmation, process ownership, cancellation with timeout, and safe handling of inherited environment/credentials.

## 33. Architecture & Data Model

**Reuse existing layers:** `omnimem-core`, `omnimem-storage`, `omnimem-mcp`, `omnimem-security`. Tambahkan **dua modul**, hanya ketika fitur dibuat:

- `omnimem-mission` (Rust library): task/agent/lease/event state models, permissions, SQLite queries. No separate database engine.
- `omnimem-dashboard` (on-demand executable/service): serves bundled static UI and loopback SSE. Proses hidup hanya selama dashboard aktif. UI tidak berjalan dalam MCP stdio process; memisahkan stdout JSON-RPC dari HTTP.

**Minimal SQLite extension:** `mc_agents`, `mc_tasks`, `mc_task_dependencies`, `mc_events`, `mc_approvals`, `mc_task_artifacts`; memakai existing `workspaces`, `memories`, dan checkpoint refs. Index pada `(workspace_id,state)`, `(agent_id,updated_at)`, dan `(event_id)`. Semua migrations versioned dan mempunyai backup/rollback strategy. Simpan payload events kecil, tanpa full prompts/raw tool logs secara default; retention configurability dan redaction wajib.

**SQLite process coordination:** transaksi pendek, busy timeout, retry bounded dengan jitter, single-writer SQLite semantics; tidak memerlukan Redis/NATS/Kafka. Jika database di drive eksternal, semua komponen mengikuti folder data canonical dan kondisi storage yang sama. Jika drive disconnect: freeze mutations + notify, jangan membuat in-memory alternate state yang disamarkan sebagai committed data.

**UI stack:** frontend ringan dapat menggunakan vanilla TypeScript/React sesuai kebutuhan yang terbukti; hindari dua SPA framework, runtime browser embedded, Electron, dan visualisasi 3D untuk fungsi dashboard dasar. Compile static assets, serve hanya localhost. Sumber data dari snapshot + SSE.

**Security:** dashboard bind ke loopback secara default, random port dan short-lived session token; non-GET endpoints pakai anti-CSRF/origin validation, no wildcard CORS, no unauthenticated external bind, log sanitization, task isolation per workspace, symlink/realpath validation sebelum file action.

## 34. Agent Identity, GitHub Lock & Human Approval

**Binding rules from PRD v1.2:** Hanya GitHub akun **`YanIanZ`**, author/committer `YanIanZ` dengan email tervalidasi yang secara eksplisit dikonfigurasi. Push hanya ke repository `github.com/YanIanZ/<approved-repo>` menggunakan credential akun `YanIanZ` dan **per-push human approval**. Tidak ada AI `Co-authored-by`, bot git signature, automatic push/merge, atau branch history rewrite. Jangan memalsukan author pihak ketiga.

Gate runtime perlu memisahkan:

- `task.review_approved` — review teknis lulus (bukan izin push).
- `git.commit_allowed` — metadata + user consent sesuai policy dan scope (bukan izin push).
- `git.push_approved_for_once` — pengguna menyetujui target, commit range, authenticated account, URL push, dan action yang **spesifik**. Approval kedaluwarsa setelah dieksekusi/cancel/target berubah.

Semua agent dalam dashboard wajib membaca canonical `AGENTS.md`; adapter host-specific menjadi shim, bukan policy berbeda. `mc_agent_status` tidak boleh menampilkan status approval palsu. Jika akun GitHub tidak dapat diverifikasi, push gagal dengan pesan actionable.

UI boleh menawarkan tombol untuk *membuat permintaan approval*; itu bukan izin permanen yang dapat digunakan kembali oleh agent. Git hooks dan server-side rules tetap defense-in-depth, bukan jaminan mutlak terhadap bypass lokal.

## 35. Anti-Overengineering & Resource Budgets (Binding)

1. **Do not redesign OmniMemo as a general multi-agent OS.** OMC adalah adapter + task view tipis atas shared memory.
2. **Default OFF:** UI, event collector, task orchestration, role spawning, graphical office, and background process tidak boleh aktif tanpa opt-in.
3. **Build smallest vertical slice:** register two agents -> create one task -> claim -> checkpoint -> handoff -> review -> dashboard shows result. Jangan membuat org-chart, role prompt builder, workflow scripting, 3D avatars sebelum alur ini lulus acceptance.
4. **No provider lock-in:** adapter capability detection lebih penting dibanding meniru sintaks Claude dan mengasumsikan kompatibel pada Codex.
5. **No mandatory framework/data stores:** Rust + existing SQLite/FTS5 cukup sampai benchmark membuktikan sebaliknya.
6. **Context budget per task:** `memory_context` default ≤600 token di OMC, configurable. Task previews ≤120 token; jangan mengirim seluruh office events ke konteks model.
7. **Disk retention:** batasi events high-level dengan retention policy (contoh target default 7 hari atau 10.000 events, dipilih paling cepat). Retention adalah kebijakan berbeda dari persistent memory.
8. **Memory-only baseline:** idle 0 server process; UI tidak boleh menyebabkan memory-only path lebih lambat/berat hanya karena modul tersedia dalam build.
9. **No false telemetry:** token/cost metrics per agent hanya bila disediakan provider/hook resmi. Jika tidak ada, tampilkan `unavailable`, bukan angka perkiraan seolah fakta.
10. **Role templates are opt-in:** 1 agent boleh mengerjakan beberapa tugas secara sekuensial; jangan paksa 5 concurrent agents.
11. **Keep cache portable:** dashboard assets static terbundle dan tidak diindeks sebagai memo. Cache dashboard ≤16 MiB target (di luar persistent DB), configurable; keseluruhan memori cache tetap menghormati setting dasar OmniMemo.
12. **Human decisions remain explicit:** tidak ada auto-approval, auto-commit, auto-push, auto-merge, atau self-review yang menyetujui kode sendiri.

**Performance targets (bukan klaim telah tercapai):** cold dashboard startup <3s pada mesin target; interactive render <1s setelah snapshot tersedia; RAM tambahan dashboard idle <100MiB setelah build release; p95 local event-to-screen <2s bila event stream tersedia. Ukur di macOS Apple Silicon dan satu mesin Linux entry-level; klaim kompatibilitas Windows setelah test.

## 36. Commands & Configuration (Proposed API)

```bash
omnimem mission init --workspace .
omnimem mission dashboard                # start local UI on demand
omnimem mission agents                   # show discovered runtimes + capabilities
omnimem mission task add "Optimize startup" --project .
omnimem mission task assign T-101 --agent codex --role engineer
omnimem mission task show T-101
omnimem mission approvals                # read-only list
omnimem mission doctor                   # runtime / storage / policy diagnostics
```

All commands above are **future interface proposals**, not existing binaries. MVP can use read-only display plus manual assignment; add `launch` only after adapter permission/safety tests.

Example config:

```toml
[mission_control]
enabled = false
mode = "observe"           # observe | coordinate (coordinate opt-in)
ui_bind = "127.0.0.1"
role_templates = false
local_office_view = false

[mission_control.events]
retention_days = 7
max_events = 10000
redact_secrets = true

[mission_control.guardrails]
require_approval_for_launch = true
require_review_for_done = true
allow_auto_push = false
allowed_github_owner = "YanIanZ"
```

Defaults harus konservatif: parsing config tidak boleh menciptakan izin implisit. Actual effective Git authenticated account tetap diverifikasi pada waktu push, bukan dianggap benar karena `allowed_github_owner` diatur.

## 37. Implementation Roadmap (Updated)

- **M0 — Memory MVP:** pertahankan v1.2 save/search/checkpoint/MCP/permissions, tanpa dashboard.
- **M1 — Mission Control Observe (P1):** project/agent registry, task state SQLite, manual task assignment, on-demand local dashboard, task board, event timeline, live status hanya bila supported, read-only Git identity indicator.
- **M2 — Cooperative Multi-agent Handoff (P1):** task MCP group opt-in, lease/CAS, checkpoint evidence, review, blocked states, independent QA, capability matrix for Codex/Claude/Gemini/OpenCode.
- **M3 — Coordinated Launch (P2):** audited agent launch adapters opt-in, isolated Git worktrees, cancellation, prompt injection and credential safety tests, approvals. No auto-push.
- **M4 — Office Visualization (P2):** optional lightweight 2D office, avatars and work animation reflecting real state. Do not backport 2D visuals into headless MCP core.

**Release rule:** tidak boleh memblokir rilis memory-only karena pekerjaan animasi UI belum selesai. Feature flag, test, dan dokumentasi harus sesuai kemampuan yang benar-benar tersedia.

## 38. Acceptance Tests — Multi-Agent Mission Control

| ID | Scenario | Expected |
|---|---|---|
| MC-01 | Codex create checkpoint -> Claude reads it via task | Same memory, strict project scope, no duplicated context |
| MC-02 | Claude Reviewer critiques Codex Engineer diff | Review evidence recorded; no automatic Git push |
| MC-03 | Gemini with unsupported session-observe | UI shows `unknown/not_observed`, not misleading `idle` |
| MC-04 | OpenCode receives task and completes via MCP | Same task schema regardless of provider |
| MC-05 | Two agents claim same task simultaneously | Single winner; loser gets conflict/owner response |
| MC-06 | Agent update retry after network/process failure | Idempotent; no duplicate checkpoint/events |
| MC-07 | Concurrent writes to same worktree | Parallel work blocked or moved to separate worktrees |
| MC-08 | Stale/contradictory memory consulted | Warning + provenance; cannot silently override validated evidence |
| MC-09 | SSD unplugged during dashboard use | Mutation fails closed; no new shadow DB; recovery documented |
| MC-10 | Dashboard closed | No background UI collector; memory-only MCP still works |
| MC-11 | UI attempts to push after QA `approved` | Denied until explicit per-push user approval + verified identity |
| MC-12 | Credentials belong to another GitHub account | Push denied; no account switch or token copy |
| MC-13 | 5 role templates enabled but 1 agent available | No forced spawn / cost; manual role assignment possible |
| MC-14 | Provider does not report tokens/cost | Metrics show unavailable, no invented consumption |
| MC-15 | UI reconnects after dropped SSE | Snapshot reloaded; missed events annotated |
| MC-16 | Malicious event/memory contains fake instructions | Treated as untrusted text, does not execute commands or change policy |
| MC-17 | Task contains sensitive credentials | Redaction before persistence and UI display |
| MC-18 | Scope includes private project B while viewing project A | No cross-project leakage without explicit ACL |
| MC-19 | CLI and dashboard start simultaneously | SQLite migrations/transactions safe, no data corruption |
| MC-20 | User requests simple memory recall | Agent not forced to load task/mission schemas or dashboard context |

## 39. Definition of Done for the New Feature

A basic Mission Control feature is complete only when **two different agent providers** can consume shared memory and cooperate on a task via a persistent task state and a visible dashboard, with safeguards for concurrent work, verified review, and explicit Git push approval. Codex, Claude Code, Gemini CLI, and OpenCode require an individually tested capability matrix; unsupported provider features are identified transparently rather than claimed as universal automation.

**Product north star:** **“Satu memori; banyak agent; satu dashboard; izin pengguna tetap menjadi keputusan akhir.”**


---

# PART V — OMNI AGENT UNIVERSAL RUNTIME (v1.4)

> **Status:** Proposed; specifications and example commands are not implemented features.
> **Hierarchy:** OmniMemo = shared knowledge; Omni Agent = portable delegation runtime; Mission Control = optional visibility/control plane. Omni Agent must remain useful without dashboard, office view, external database, or resident daemon.

## 40. Product Definition: What Omni Agent Is / Is Not

**Omni Agent** is a local-first, provider-neutral *subagent and task delegation system* running across Codex, Claude Code, Gemini CLI, OpenCode, and future compatible runtimes. It coordinates isolated tasks via a small common contract, bounded context packages, durable checkpoints, and capability-aware adapters. A user may start with Codex in VS Code, hand off to Claude Code in a terminal, send independent QA to Gemini CLI, and inspect state from OpenCode or Mission Control without manually copying a whole transcript. A *workspace* may span distinct IDE windows; *projects* remain isolated by default even when the same disk stores their memory.

**Omni Agent IS:** context broker, task scheduler, delegation tool, cross-host adapter layer, guardrail enforcer, selective context exporter, progress/evidence tracker. **Omni Agent IS NOT:** an autonomous LLM or model provider; a replacement for Codex/Claude/Gemini/OpenCode; a method to read private conversations from unintegrated IDEs; guaranteed ability to control arbitrary running IDE sessions; a framework requiring users to install all providers; a reason to run five workers for every task.

Key principles:
1. **Cross-provider first:** each provider remains an independent runtime using its own authentication, model, quotas, permissions, and supported features.
2. **Task-structured, not transcript-based:** only purpose-specific task capsules and verified results cross provider boundaries.
3. **Performance means useful outcomes per total tokens/time/cost**; never claim magic speed-ups or savings.
4. **One-agent default:** dispatch a subagent only if there is explicit user delegation, clear independence, or measured benefit.
5. **Strict permission intersection:** effective action permission = intersection(user approval, repo policy, project scope, adapter capability, runtime permissions).
6. **OmniMemo is the source of truth for shared task state.** Do not build a second overlapping memory database.

## 41. User Stories & Priority

| ID | User story | P | Acceptance summary |
|---|---|---|---|
| OA-01 | As a Codex user I can delegate code review to Claude, even in another terminal | P0 | A bounded capsule is dispatched; Claude returns evidence-linked review |
| OA-02 | As a Claude user I can delegate investigation to Gemini CLI without sharing entire chat | P0 | Task reference and minimal relevant context, not full transcript |
| OA-03 | As an OpenCode user I can take over task T with decisions preserved | P0 | Restore latest accepted checkpoint, report stale evidence |
| OA-04 | I can see work done in two IDEs as one canonical task | P0 | Same task ID across agents and UI, no invented status |
| OA-05 | I can choose manual/native/cross-provider execution per task | P0 | Clear capabilities and fallback status |
| OA-06 | I can cap delegation by maximum workers and token budget | P0 | Bounded scheduling, stop on exhausted budget |
| OA-07 | Multiple agents edit independent files without trampling one another | P0 | Worktree ownership, conflicts detected before applying changes |
| OA-08 | I can run two separate ideas/projects on one machine | P0 | Project ACL and memory isolation enforced |
| OA-09 | I can relocate data to external SSD without losing coordination | P0 | Shutdown/restart/reopen/restore failure behavior is tested |
| OA-10 | I can inspect why a subagent was chosen and what it returned | P1 | Explainable dispatch reason and evidence available |
| OA-11 | If a provider isn't installed, task still works through manual handoff | P0 | No fake launch, task capsule export/import available |
| OA-12 | I can visualize live tasks in optional Mission Control | P1 | Observed event vs inferred state visibly distinguished |

## 42. Supported Execution Modes

### 42.1 Native-subagent mode

Register existing host-native subagents as **capabilities**, not as a unified implementation. Anthropic Claude Code, Gemini CLI, and OpenCode document their own subagent mechanisms; provider-specific restrictions apply, including whether subagents can further delegate. Codex has CLI, SDK and app-server integration routes depending on installed distribution. Omni Agent must not assume the same programmatic access for all. A native subagent is host-controlled; Omni Agent observes or delegates only if integration hooks actually exist.

### 42.2 Cross-runtime delegated mode

Launch a *new, bounded worker process* only through a version-validated CLI/SDK/API adapter and only when user consent, provider availability and runtime permissions permit. Do not inject commands into a private interactive IDE chat by screen scraping or internal files. Prefer supported structured output (JSON/JSONL), workdir, timeout, and read-only permission flags. On headless workers, **process != active IDE chat**: show that distinction.

### 42.3 Manual/portable handoff mode

When no safe dispatch API is supported, generate a signed/hashed **Task Capsule** with task ID and references. User may paste or load it in any IDE. Worker claims the task via MCP; its result is re-attached to the same task record. No fabricated presence or output streaming.

### 42.4 Observe-only mode

If an existing IDE is connected via MCP but cannot be controlled, expose shared memory/tasks and accept worker-posted checkpoints; display `not_observed` rather than idle/running when no reliable event source is available.

## 43. Cross-IDE Connectivity & Shared Task Bus

**Control plane:** one SQLite-backed persistent task/assignment/event schema reused from Mission Control, plus an on-demand orchestration process. MCP `stdio` supports per-host tools; all instances open the same configured local database *only when filesystem locking and SQLite concurrency semantics allow*. Optional bound-to-loopback HTTP/SSE provides dashboard updates; not required for worker cooperation. Cross-machine coordination is explicitly **not** supported in MVP.

**Flow**:
1. Each IDE/agent registers a `client_instance_id`, `runtime_id`, `workspace_id`, `capabilities`, and `observed_at` via MCP handshake or read-only CLI discovery.
2. User/host submits a task; coordinator assigns persistent `task_id` and `revision`, stores allowed files and success criteria.
3. Worker obtains exclusive lease (atomic CAS on task revision); tasks without claimed leases remain queued.
4. Worker receives short context capsule, reads only permitted files, writes a checkpoint and evidence.
5. Coordinator routes next task or manual handoff; Mission Control displays observed events, not guessed worker activity.
6. On cancellation or disappearance, lease expires; a retry runs only after comparing checkpoint, side effects, and revision.

**IDE independence:** an IDE window never owns the canonical task; it holds only an ephemeral connection to it. Closing VS Code must not delete Codex's shared tasks, and closing Mission Control must not stop independently supported worker execution. Cancellation of a worker should terminate only an explicitly managed child process, not someone else's terminal session.

**No automatic arbitrary cross-project share:** accessing idea/project B from project A needs the user's explicit consent; workspace selectors and ACLs are enforced on both query and task claim.

## 44. Core Runtime Components

| Component | Purpose | Implementation bias |
|---|---|---|
| Agent Registry | Discovered executables, version, capability flags, local IDs | SQLite + executable checks, no global always-on scanner |
| Task Router | Accept/reject/defer delegation by dependency and expected value | Deterministic rules, no LLM scheduler for MVP |
| Context Capsule Builder | Bounded task objective/constraints/evidence references | Reuse OmniMemo memory search and token budget |
| Runtime Adapter | Provider-specific process/session interface | 4 small adapters, capability detection at startup |
| Lease Coordinator | Atomic task claim, optimistic revision, timeout | SQLite transaction; no Redis/RabbitMQ |
| Artifact/Result Collector | Diff hashes, test output refs, summary | Files on disk or SQLite metadata; no full log duplication |
| Budget Guard | Track requests/usage only when surfaced; enforce local hard bounds | Max runs, turns, wall clock, bytes; unknown token reports explicit |
| Policy Gate | File access, command allowlist, GitHub owner lock, push approvals | Reuse canonical v1.2/v1.3 guardrails |
| Event Timeline | Optional UI updates and audit | Existing Mission Control event schema |

**Boundary rule:** isolated modules are warranted only when at least two features use them. P0 can be a single Rust crate's internal modules; do not split into seven services or crates before real demand.

## 45. Omni Agent Task Contract (OATC v1)

Use a versioned JSON envelope and canonical JSON Schema for interoperability. Below is an illustrative compact payload (not a final validated schema):

```json
{
  "schema_version": "oatc/1",
  "task_id": "T-104",
  "project_id": "p-sourbycraft",
  "workspace_id": "w-local",
  "source": { "runtime": "codex", "client_instance_id": "cli-a" },
  "target": { "runtime": "claude", "role": "reviewer", "mode": "delegated" },
  "objective": "Review the plugin startup patch for regressions",
  "scope": { "read_paths": ["src/**"], "write_paths": [] },
  "context": {
    "capsule_id": "C-023",
    "memory_refs": ["M-18", "M-43"],
    "git_base_commit": "<resolved-at-dispatch>",
    "relevance": "startup"
  },
  "limits": { "context_tokens": 450, "max_turns": 6, "wall_seconds": 300 },
  "permissions": { "read": true, "edit": false, "push": false },
  "completion": { "required": ["findings", "file_references", "test_recommendations"] },
  "revision": 4,
  "idempotency_key": "task104-review-v1"
}
```

**Output contract:** `task_id`, `status`, `summary` (default max 200 words), `findings` with severity and file/range/evidence, `changed_files` (if any), `tests_executed` with actual pass/fail/skipped, `remaining_work`, `token_usage` with measurement source or `null`, `cost` or `null`, `artifact_refs`, `memory_refs`, `policy_violations` and `revision`. Results must never contain private model reasoning, raw credentials, hidden chain-of-thought, or unsanitized full session transcripts.

**Runtime state machine:** `created → queued → claimed → running → submitted → reviewing → done` with alternative transitions to `blocked`, `failed`, `canceled`, `timed_out`, `stale`, `needs_approval`. `done` means passing review/tests appropriate to risk, *not* permission to commit, merge or push. Every transition increments revision and appends a deduplicated audit event.

**Artifact integrity:** persist relative path + content hash + source commit + run ID, not raw source files as memory. Reject symlink escape, traversal (`../`), and workspace root mismatch. Check hashes before consuming from another agent.

## 46. Token Efficiency: Context Capsule & Delta Handoff

**Objective:** improve task success / *total* input + output tokens used by *all* workers plus coordinator, including MCP tool schema, retries, validation calls, and summarization. Saving parent context can raise total spend; never present it as universal savings.

**Context Capsule construction:**
1. Resolve project, branch, trust scope, task type, current Git status and evidence freshness.
2. Fetch up to the target budget from OmniMemo: architecture facts, relevant decisions, tests, and latest checkpoint. Include stable memory IDs, not full text for every referenced entity.
3. Include task objective, constraints, allowed paths, acceptance criteria, security rules, and `must_not` list.
4. Provide targeted file paths; worker reads required file ranges on demand, not the entire repository.
5. Cap output length; use structured outcome and source refs rather than raw tool logs.
6. Store delta (changed files, decisions, test outcomes) for next worker; deduplicate repeated handoff material.

**Capsule tiers** (defaults to be benchmarked and user-overridable): `micro` ≤150 token factual capsule (read-only inspection); `standard` ≤450 token handoff; `extended` ≤1,200 token complex isolated engineering. These are *capsule-only* budgets; full worker context, system instructions and scanned files are not included. Show actual total telemetry separately.

**Reuse rule:** do not create a new worker if a suitable existing one can safely continue with lower expected re-briefing cost. Reuse only when runtime actually supports session resume and task/project scope is unchanged. Never resume another user's private conversation.

**Prompt caching:** do not conflate OmniMemo disk cache with a provider's prompt cache; no guarantee of cache hit or savings. Preserve stable static prefix where supported; avoid storing provider tokens in persistent memo.

**Optimization objective for dispatch** (qualitative MVP; numeric weights only after benchmark):
`expected_value = predicted_quality_gain + predicted_wall_time_gain - delegation_tokens - tool_setup - coordination_risk - cross_provider_cost - merge_conflict_risk`.
If score is uncertain or nonpositive → do the job in the current agent. For very simple tasks, never spawn a reviewer merely to demonstrate multi-agent.

## 47. Scheduling, Concurrency & Quality

### 47.1 Task eligibility

Eligible for concurrent execution if tasks have independent acceptance criteria, limited dependencies, and non-overlapping mutable resources. Read-only research tasks may run in parallel. Mutating tasks default to sequential mode unless isolated Git worktrees exist and the user has enabled parallel edits.

### 47.2 Scheduling modes

- `economy`: single worker; no speculative delegation; 1 retry max and only on safely idempotent stages.
- `balanced`: default, one worker normally; up to 2 independent workers when verified useful.
- `performance`: up to 3 concurrent workers and isolated worktrees when user explicitly enables; still bounded by provider limits, token budget and quality gates.

No recursive subagents through Omni Agent in v1.4; coordinator depth=1. Host-native subagent recursion remains controlled by host configuration and is not promised to be intercepted.

### 47.3 Failure and conflict handling

- Workspace lease: one mutating owner per worktree/file allocation. Reviewer may read a frozen diff without claiming write ownership.
- When two tasks target same file, serialize or branch/worktree separate; no silent overlapping edits.
- Use optimistic concurrency (`revision`) for task and memory updates, unique idempotency key for retries.
- Detect provider timeout, rate limits, unavailable CLI, storage disconnection, and partially applied changes. Mark as `blocked`/`needs_review` without fabricated success.
- On cancellation, never kill unowned OS process. Only terminate child owned by a particular execution run; record side effects.
- Require review of changed diff and impacted tests; do not accept self-approval as independent verification.

### 47.4 Operator-visible performance metrics

Measure end-to-end token usage per worker, aggregated token usage, calls, duration, successful task completion, diff conflicts, retry counts, and optional actual API spend. Unknown value is `unavailable`; estimates must be labeled `estimated`, never billed as fact. Run benchmark against the same set of realistic tasks with equal quality gates.

**Provisional success criteria:** aim ≥20% median reduction in total tokens on repeated handoff workloads at noninferior acceptance-test pass rate; aim ≥25% median lower handoff context than naive transcript copying; do not publish claims without measurement. It is acceptable to fail these targets and improve design; no arbitrary hard promise of maximum performance.

## 48. Capability Matrix & Adapter Contracts

| Runtime | Native subagents | Independent headless / programmable execution | Cross-IDE coordination | Important limitations |
|---|---|---|---|---|
| Codex | Provider features depend on Codex product/version | `codex exec`, SDK, or app-server when supported | Shared task/MCP layer; cross-runtime dispatch via adapter | Cannot assume all interactive Codex sessions are controllable |
| Claude Code | Documented custom subagents | `claude -p` output-format JSON/stream-json where supported | MCP and task capsules | Own account/rate limits, native subagents have private contexts |
| Gemini CLI | Documented local and remote subagents | Headless `gemini -p --output-format json` where supported | MCP/task capsule, remote capabilities when configured | Remote/A2A support does **not** automatically bridge every third-party runtime |
| OpenCode | Documented primary/subagents | `opencode run --format json` / server mode version-specific | MCP and task capsules | V1/V2 config differences; detect rather than guess |
| Unknown client | `unknown` | `unknown` | Manual capsule export/import | Do not invent capability or status |

**Adapter interface (conceptual Rust pseudocode):**

```rust
trait RuntimeAdapter {
    fn detect(&self) -> CapabilityReport;
    fn validate_permissions(&self, task: &Task) -> Result<(), PolicyError>;
    fn launch_bounded(&self, capsule: &ContextCapsule) -> Result<RunHandle, Error>;
    fn observe(&self, run: &RunHandle) -> Result<ObservedStatus, Error>;
    fn cancel_owned(&self, run: &RunHandle) -> Result<(), Error>;
    fn normalize_result(&self, raw: &str) -> Result<TaskResult, Error>;
}
```

This is an **illustrative contract**, not a mandate to build 20 generic traits. Implementation should start with 2 adapters that prove cross-provider dispatch end-to-end (Codex + Claude), followed by Gemini and OpenCode.

**Detection order:** executable discovered → version parsed → documented CLI `--help` capability flags → authenticated by runtime's own supported checks (never store credentials) → safe read-only smoke test with user opt-in → capability status `available | requires_setup | unsupported | unknown`. Provider availability and rates vary; missing adapters must not prevent memory-only usage.

**Official references checked October 18, 2026:**
- Codex integration: https://developers.openai.com/blog/codex-as-a-platform
- Claude Code subagents: https://code.claude.com/docs/en/sub-agents
- Claude CLI (print mode): https://docs.anthropic.com/en/docs/claude-code/cli-usage
- Gemini CLI subagents: https://geminicli.com/docs/core/subagents/
- Gemini CLI headless: https://geminicli.com/docs/cli/headless/
- OpenCode agents: https://opencode.ai/v2/docs/agents
- OpenCode CLI: https://dev.opencode.ai/v2/docs/cli/commands/
- MCP spec: https://modelcontextprotocol.io/specification/2026-07-28

## 49. MCP & CLI Surface — New v1.4 Proposals

Avoid adding all capabilities as MCP tool schemas to every agent. Expose four essential task tools in base Omni Agent mode, with advanced tools gated by module features:

| MCP tool | Action | Notes |
|---|---|---|
| `omni_task_create` | Create task and scoped capsule | Does not launch automatically |
| `omni_task_claim` | Atomically claim assigned task | Lease/revision required |
| `omni_task_checkpoint` | Save delta, progress, and evidence | Secrets redacted |
| `omni_task_result` | Submit structured work result | Cannot auto-approve/push |
| `omni_agent_delegate` (opt-in) | Dispatch a verified bounded adapter | Explicit mode/permissions; privileged |
| `omni_agent_status` (optional) | Get observed worker status + budget | Unknown not treated as idle |

```bash
# Proposed CLI, not runnable until implemented
omnimem agent doctor
omnimem agent list --capabilities
omnimem agent task create "Review startup performance patch" --project .
omnimem agent delegate T-104 --runtime claude --mode read-only --approve-launch
omnimem agent task handoff T-104 --runtime gemini --mode manual
omnimem agent task show T-104 --events
omnimem agent budget --task T-104
omnimem agent cancel T-104        # managed owned child process only
```

**Default execution mode**: `manual` unless opt-in dispatch capability is enabled by the user. User may approve one worker launch without blanket approving all future runtime invocations. No automatic push in any mode.

## 50. Proposed Config — Lean Defaults

```toml
[omni_agent]
enabled = true                  # registry + manual task tools, no background process
execution_mode = "manual"     # manual | native | delegated
strategy = "balanced"        # economy | balanced | performance
max_concurrent = 2
max_depth = 1
provider_auto_discovery = false
persist_transcripts = false

[omni_agent.context]
capsule_default_tokens = 450
capsule_max_tokens = 1200
store_raw_logs = false

auto_compact = true

[omni_agent.budget]
max_worker_turns = 8
max_run_seconds = 600
max_retries = 1
max_total_tokens = 20000        # stop proactively only when reliable meter available
on_missing_usage = "bounded_by_turns_and_time"

[omni_agent.security]
allow_cross_project = false
allow_unattended_write = false
allow_auto_commit = false
allow_auto_merge = false
allow_auto_push = false
require_explicit_launch_approval = true
allowed_github_owner = "YanIanZ"

[omni_agent.runtime]
allowed = ["codex", "claude", "gemini", "opencode"]
allow_install_agents = false
```

**Configuration note:** `max_total_tokens` is a budget target; a hard global cutoff is not guaranteed when some runtimes provide usage only after execution. The actual hard guard uses supported provider limits and local `max_worker_turns` / `max_run_seconds`. `enabled=true` is tool exposure, not unattended execution or daemon installation. Profile all resources before selecting production defaults.

## 51. Mandatory Security, Trust & GitHub Rules

1. **No credentials replication:** Providers continue to use their own locally configured authentication; tokens/passwords/SSH keys are never copied between workers or stored in OmniMemo.
2. **No bypass of CLI permissions:** Do not use `--dangerously-skip-permissions`, unsafe YOLO equivalents, or scripted credential prompts. If a provider cannot run read-only safely, require manual handoff.
3. **Project-scoped capabilities:** inherit the narrowest intersection of user, repository, agent, and runtime permissions. Paths resolve within workspace; prohibit symlink escapes.
4. **Untrusted content:** memory records, log output, task comments, agent recommendations and retrieved web/file contents never override policy; prompt injection attempts are treated as data.
5. **No invisible agent spawning:** any new worker appears in task events with runtime/model if known, initiator, task scope, and run budget.
6. **GitHub identity:** owner `YanIanZ` only for authorized remote pushes; newly agent-authored commits use configured Git author/committer `YanIanZ` with verified email supplied by user, no AI-generated coauthor footers. Do not rewrite legitimate historical authorship.
7. **Separate Git permission gates:** editing, committing, reviewing, merging and pushing are distinct privileges. By default Omni Agent may not auto-commit, auto-merge or auto-push.
8. **Per-push explicit human approval:** even approved QA reviews or completed tasks cannot authorize `git push`. Verify authenticated GitHub identity and effective push URL **at time of push**; refuse on mismatch or uncertainty.
9. **No force-push / history rewrite / remote mutation** by any worker without explicit separate human action allowed under repo policy.
10. **Disk absence:** fail closed on missing external drive; no shadow data folders, silent fallback, or detached shadow queues containing private task data.
11. **Process ownership:** never attach to, inspect private histories of, interrupt, or kill arbitrary unrelated IDE/agent processes. Read only opt-in MCP/task state and adapter-owned processes.
12. **Provider policy compliance:** do not implement unsupported subscription-to-API key extraction, reverse engineering of credential stores, or impersonation across providers.

## 52. Anti-Overengineering: Hard Stop Checklist

Before adding a new module or feature, answer all five:

- Is it required by a defined OA story or a failing acceptance test?
- Can SQLite + Rust + existing OmniMemo tools already solve it?
- Does it measurably improve quality, token efficiency, reliability, or safety?
- Can it be disabled without breaking the memory-only core?
- Is there a simpler approach with fewer dependencies and fewer platform assumptions?

If the first answer is no, **do not implement**. For P0 specifically, **DO NOT** add: Kubernetes, Redis, RabbitMQ, Neo4j, vector DB, distributed consensus, custom A2A gateway, browser automation to control IDE UI, full autonomous planner, 3D office, model marketplace, autonomous self-improving prompts, continuous indexing, always-on telemetry, or 20 role-specific subagent templates.

**P0 scope = 2 provider adapters + 4 essential task tools + one capsule schema + SQLite task bus + 1 end-to-end benchmark suite.** Reuse v1.3 dashboard and guardrails; no new task board.

## 53. Benchmark, Instrumentation & Release Gates

Benchmark tasks (same prompts / same repository state / comparable model entitlement / matching tests):
1. **Tiny bug fix**: single agent baseline vs auto-route. Expected policy: no delegation; minimal overhead.
2. **Cross-agent review**: Codex patch -> Claude review via 450-token capsule vs full transcript copy.
3. **Independent investigation**: two read-only diagnoses in parallel; measure wall time, aggregate tokens, utility.
4. **Cross-IDE handoff**: Claude terminal -> OpenCode desktop with persistent checkpoint; no raw transcript.
5. **Multiple separate projects**: intentional project A/B isolation, no mixed results.
6. **Disruption**: SSD unplug, child crash/timeout, provider rate limit, second task claim, stale Git base.

Required telemetry: wall time end-to-end, token input/output per runtime when available, total measured/estimated tokens with provenance, launch overhead, output bytes, context capsule size, number of turns, acceptance pass rate, task conflicts, verified user approvals, and failure reason.

Hard release gates: **security and project isolation, no unauthorized push, no hallucinated provider presence/usage, no database corruption, and no data loss under documented supported filesystem assumptions.** Soft performance goals are measured and published without overstating results.

## 54. Acceptance Test Matrix — Omni Agent

| ID | Test | Expected |
|---|---|---|
| OA-T01 | Codex creates task; Claude CLI claims via MCP | One canonical task ID, no copied raw transcript |
| OA-T02 | Claude returns reviewer findings | File/line evidence, no self-approval or push |
| OA-T03 | Gemini CLI takes over handoff in another terminal | Correct checkpoint and scope, no previous agent credentials |
| OA-T04 | OpenCode lacks expected CLI flag | Adapter marks unsupported and falls back to manual capsule |
| OA-T05 | IDE closes mid-task | Canonical persisted task remains; status not falsely asserted |
| OA-T06 | Cross-project claim is attempted | Denied without explicit project access approval |
| OA-T07 | 2 workers try to claim one task | Exactly one CAS winner; loser gets current lease owner |
| OA-T08 | Mutating tasks target same paths | No parallel execution in same worktree; isolate or serialize |
| OA-T09 | Read-only subtasks have separate scopes | May execute concurrently within cap |
| OA-T10 | Budget exhausted before task completion | Worker stops or marks bounded_unknown depending adapter; partial results preserved |
| OA-T11 | Runtime provides no token usage | Display `unknown`, not 0 or guessed number |
| OA-T12 | Delegation not worth cost on small change | One-agent mode; no spawned worker |
| OA-T13 | Raw secret appears in worker output | Secret redacted and never persisted to memory or dashboard |
| OA-T14 | Task output contains instruction to disable guardrail | Instruction ignored and flagged as untrusted data |
| OA-T15 | External SSD disconnected during checkpoint | Fail closed, no fallback DB, durable recovery strategy documented |
| OA-T16 | Retry same run with same idempotency key | No duplicate checkpoint or artifact records |
| OA-T17 | Local child crashes after edits | Unknown side effects marked; no automatic unsafe retry |
| OA-T18 | Cancel from another IDE | Only own managed process stopped; unrelated session untouched |
| OA-T19 | Provider authentication belongs to user B | Never copied; no cross-provider impersonation |
| OA-T20 | Agent tries push to non-YanIanZ repo | Denied even if QA passed |
| OA-T21 | Remote YanIanZ but authenticated GitHub account differs | Push denied |
| OA-T22 | Worker sets generated-by / Co-authored-by AI footer | Repo commit policy rejects auto AI attribution |
| OA-T23 | Mission Control disabled | Delegation/manual handoff still works |
| OA-T24 | No runtime configured | Memory-only MCP remains usable; manual capsule possible |
| OA-T25 | Context capsule includes stale source commit | Worker receives stale warning and must verify before changing code |
| OA-T26 | Case-insensitive case path/symlink escape | Path ACL blocks escape outside permitted tree |
| OA-T27 | Multiple provider installations or OpenCode V1/V2 | Detect exact runtime version and feature flags, do not assume |
| OA-T28 | Device sleeping, agent loses lease | Recovery safe and explicit; abandoned task not fabricated as done |
| OA-T29 | Separate IDE views inspect same task | They agree on revision and checkpoint; missing events not invented |
| OA-T30 | Comprehensive benchmark | Quality vs token/time measured fairly, no unverifiable "maximal" claim |

## 55. Implementation Plan and Final Definition of Done

**M0 — Proof of interop (P0)**: OATC v1 schema, SQLite task extension, core four MCP tools, one capsule builder, two read-only runtime adapters (Codex and Claude), manual fallback, CLI inspection. Demo: Codex requests task review -> Claude returns structured evidence -> Codex consumes reviewed outcome. No auto-start unless user opt-in.

**M1 — Reliable handoff (P0)**: Gemini and OpenCode adapters, agent capability checks, lease and CAS, idempotency, error paths, external SSD safe recovery, Git permission gates, project isolation.

**M2 — Efficient safe parallelism (P1)**: read-only independent workers, optional isolated worktrees for editing, deterministic dispatch heuristic, reuse/compaction, measured benchmarking and telemetry.

**M3 — Mission Control UI extension (P1)**: visible Omni Agent roster, cross-IDE task timeline, capsule metadata, observed vs unknown status, approvals. Reuse existing UI; do not make mission UI a dependency for the core.

**M4 — Optional advanced coordination (P2, only with evidence)**: durable provider resumptions, streaming event bridges, A2A adapter where genuinely demanded by a real client. Do not include cloud or distributed scheduling in MVP.

**Definition of done for Omni Agent v1.4**: in a supported local environment, at least Codex and Claude can complete an authenticated and scoped cross-provider task handoff end-to-end; Gemini and OpenCode adapters have documented verified capabilities or explicit fallback; task claims are concurrency-safe; capsule and result have provenance; Git and privacy rules block unauthorized actions; benchmark reports total token/time impacts honestly; no additional heavy daemon/DB is required.

**Vision statement:** **“Satu memori, banyak agent, banyak IDE—tanpa membayar konteks yang sama dua kali jika bisa dihindari.”**
