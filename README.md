# OmniMemo 0.1.0

Memory dan handoff lokal untuk coding agent, dibuat dengan **Swift + MongoDB** sesuai revisi pengguna. Ini MVP-1 dari PRD v1.2, bukan seluruh roadmap.

Satu executable menyediakan CLI dan MCP stdio. MongoDB menyimpan record; folder lokal menyimpan pointer store dan cache disposable. Semua agent pada proyek yang sama membaca database yang sama. Tidak membaca history privat agent dan tidak memerlukan LLM/API key.

## Yang tersedia

- Empat tool MCP: `memory_save`, `memory_get`, `memory_context`, `memory_checkpoint` melalui SDK Swift resmi.
- CLI save/search/show/list/delete/export, checkpoint, context, status, doctor dan cache.
- Project binding saat proses diluncurkan; query record selalu difilter project ID.
- Metadata agent/branch/commit, hash bukti file, status `unverified`/`active`/`stale`.
- Unique indexes untuk deduplikasi dan idempotency; teks bilingual tanpa stemming dan pencarian literal code symbol.
- Context ringkas dengan batas konservatif termasuk allowance envelope MCP. Checkpoint terbaru tetap tersedia jika task tidak cocok dengan pencarian.
- Cache disk default 32 MiB, TTL 24 jam, eviction; key mencakup record dan bukti terkini. Database tetap diperiksa setiap retrieval.
- Adapter **project-scoped** Codex/Claude, preview default, apply eksplisit, backup, uninstall yang menjaga setting lain.
- Dua skill: recall dan handoff. Template canonical di `Sources/OmniMemoCore/Skills`; `skills` adalah symlink untuk distribusi.

## Persyaratan

Build ini diuji pada macOS Apple Silicon, Swift 6.4, MongoDB 7.0.31. Minimum package macOS 13; build minimum OS belum diuji secara terpisah. Linux/Windows belum didukung/dipaketkan; implementasi hash saat ini memakai CryptoKit. Swift language mode 5 menjaga kompatibilitas library; compiler yang dipakai Swift 6.

MongoDB lokal **wajib berjalan**. Ini menggantikan keputusan Rust/SQLite dan syarat tanpa database service dalam PRD asli. MongoKitten digunakan karena driver Swift resmi MongoDB telah diarsipkan. SDK MCP yang terkunci 0.12.1 mendukung handshake era 2025; kompatibilitas protokol 2026 tidak diklaim.

## Build

```sh
cd /Volumes/Ext/MinionsProject/OmniMemo
./scripts/swift.sh build
./scripts/package.sh
```

Artifact default: `/Volumes/Ext/DevCache/OmniMemo/dist/0.1.0/omnimem`. Simpan executable **bersama bundle skill** di direktori yang sama. Package cache, checkouts, module cache dan hasil build diarahkan ke `/Volumes/Ext/DevCache/OmniMemo/swift`; ubah `OMNIMEM_BUILD_CACHE` untuk mesin lain. Tidak perlu Xcode project atau server aplikasi.

## Mulai

Bila belum memiliki server MongoDB yang sesuai, jalankan instance khusus OmniMemo; script tidak mengaktifkan login/background service Homebrew:

```sh
./scripts/mongodb.sh start  # loopback 127.0.0.1:27018, dbPath di Ext

BIN=/Volumes/Ext/DevCache/OmniMemo/dist/0.1.0/omnimem
DATA=/Volumes/Ext/DevCache/OmniMemo/data
PROJECT=/Volumes/Ext/MinionsProject/OmniMemo

"$BIN" --data-dir "$DATA" --project "$PROJECT" init \
  --mongo-uri mongodb://127.0.0.1:27018/omnimemo

"$BIN" --data-dir "$DATA" --project "$PROJECT" memory save \
  --kind decision --title 'Storage pilihan' \
  --content 'Gunakan Swift dan MongoDB.' --source Package.swift

"$BIN" --data-dir "$DATA" --project "$PROJECT" context 'storage' --max-tokens 1000

"$BIN" --data-dir "$DATA" --project "$PROJECT" checkpoint \
  --done 'Core selesai' --next 'Verifikasi integrasi host' \
  --tests 'swift test: hasil aktual' --changed-file Package.swift
```

Gunakan `memory save --stdin` bila teks tidak ingin muncul di daftar process/shell history. Jangan memasukkan secret. URI berkredensial harus melalui `OMNIMEM_MONGO_URI`; URI yang disimpan di metadata tidak berisi user/password. MVP menerima `mongodb://`, belum `mongodb+srv://`.

Resolusi lokasi: `--data-dir` → `OMNIMEM_HOME` → `~/.config/omnimem/location.json` → `~/.local/share/omnimem`. `init --set-default` secara eksplisit menulis pointer user-level dengan backup. Query/status/MCP tidak menginisialisasi database atau folder pengganti ketika storage hilang. Port dan dbPath MongoDB independen dari folder metadata/cache.

## Integrasi Codex dan Claude

Siapkan folder metadata dengan `init`, lalu lihat tambahan yang akan dibuat:

```sh
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --agents codex,claude
# Setelah meninjau preview:
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --agents codex,claude --apply
```

Installer menulis `.codex/config.toml`, `.mcp.json`, dua skill canonical dalam `.agents/skills`, serta shim skill Claude yang menunjuk sumber yang sama. Scope adalah proyek terpilih; konfigurasi global tidak diubah. `--config-root /path/staging` dapat menyiapkan hasil untuk review tanpa menyentuh proyek asli. Server ID unik per project; perintah MCP terikat root tersebut dan memanggil `mcp serve --stdio`. Restart/approve MCP sesuai host. Installer tidak menjalankan Git hooks atau mengubah identitas Git.

```sh
"$BIN" --data-dir "$DATA" --project "$PROJECT" uninstall --apply
```

Uninstall hanya menghapus entri yang masih cocok dengan manifest. Jika entri milik installer diedit, proses menolak penghapusan dan meminta review manual. Backup tetap di `.omnimemo-installer/` dengan direktori privat dan file mode 600; folder itu di-ignore Git. Hapus backup secara sadar bila berisi setting sensitif lama. Pemasangan ulang dengan host/path yang berbeda dilakukan setelah uninstall.

## Batas context

`--max-tokens` didukung pada 256–16384; budget yang tidak cukup untuk metadata ditolak. `estimated_tokens` adalah **upper bound berbasis UTF-8 bytes**, bukan hasil tokenizer model. Perhitungan mencakup escaping teks dan envelope MCP dengan cadangan request ID 64 byte; request ID fixture lebih pendek dari batas itu. Hasil bisa jauh lebih pendek dari kapasitas model. Overhead deklarasi tool/skill di host tidak termasuk budget satu response dan harus dihitung terpisah untuk benchmark biaya total.

Tidak ada klaim persentase penghematan, recall@k, RAM atau latency target yang sudah tercapai. Batas 32 MiB hanya cache; database, journal WiredTiger, log, backup dan build cache dihitung terpisah.

## Pengujian

```sh
./scripts/test-mongo.sh start  # port 27019; bukan server/data produksi
OMNIMEM_TEST_MONGO_URI=mongodb://127.0.0.1:27019/omnimemo_tests \
OMNIMEM_TEST_ROOT=/Volumes/Ext/DevCache/OmniMemo/test-workspaces \
  ./scripts/swift.sh test

python3 Tests/mcp_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.1.0/omnimem
python3.12 Tests/cli_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.1.0/omnimem
./scripts/test-mongo.sh stop
```

Suite saat build ini: **19 XCTest lulus, 0 gagal, 0 skip**, ditambah kedua smoke test pada artifact release. Python 3.11+ diperlukan untuk parser TOML di smoke test CLI; runtime OmniMemo tidak memerlukan Python.

Tes MongoDB nyata mencakup beberapa koneksi penulis, persistensi, isolasi, dedup, secret rejection, evidence staleness, cache invalidation dan metadata hilang. Klien Python independen menguji wire MCP dan handoff antara dua subprocess berlabel fixture Codex/Claude. Itu **bukan** klaim uji percakapan live berbayar pada kedua produk. Tanpa `OMNIMEM_TEST_MONGO_URI`, tes database diberi status skip, bukan dianggap lulus.

## Trust dan batas MVP

`active` berarti sumber file masih cocok dengan hash; itu tidak membuktikan interpretasi semantik atau kebenaran klaim tes. Memory adalah data tidak tepercaya, bukan instruksi sistem. Provenance agent adalah label, bukan autentikasi. Project filtering melindungi kontrak MCP, bukan menghalangi proses lokal yang sudah punya akses langsung ke MongoDB/filesystem. Instance script hanya bind loopback; autentikasi MongoDB/izin OS harus diatur sesuai lingkungan pengguna. Secret filter bersifat heuristik dan bukan jaminan mendeteksi semua format rahasia.

Belum tersedia: migration/relocation transaksi MongoDB, actual drive-unplug recovery, konflik otomatis/revision ledger, graph, hooks auto-capture, HTTP, empat adapter penuh, embedding, cloud sync dan benchmark ROI. Jangan memindahkan WiredTiger dbPath saat server berjalan. Gunakan backup/restore MongoDB yang sesuai; folder cache bukan backup database.

Aturan proyek ada di `AGENTS.md`; PRD asli dipertahankan di `docs/OmniMemo_PRD_v1.2_Guardrails.md`, dengan koreksi pengguna tercatat di `SPEC.md`. Riwayat lokal Git menggunakan identitas pemilik yang sudah dikonfigurasi. Tidak ada remote/push otomatis.

## Referensi

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [MongoKitten](https://github.com/orlandos-nl/MongoKitten)
- [Status driver Swift MongoDB](https://github.com/mongodb/mongo-swift-driver)
- [Codex MCP](https://developers.openai.com/codex/mcp/)
- [Claude MCP](https://code.claude.com/docs/en/mcp)
