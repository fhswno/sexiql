# SexiQL

The SQL client macOS deserves. Supports Postgres, MySQL, SQLite and Redis in a fast, low-overhead, modern native app which closely follows macOS 26's design conventions.  

```
┌──────────────┬─────────────────────────────────────┬──────────────┐
│  Sidebar     │  Tab bar · Run · Explain · Export   │  Inspector   │
│              │ ┌─────────────────────────────────┐ │              │
│ Connections  │ │ SQL editor — highlighting,      │ │ Connection   │
│ Schema       │ │ ⌘⏎ run, line numbers            │ │ details      │
│ Saved        │ ├─────────────────────────────────┤ │ Result info  │
│ History      │ │ Results grid — sort, filter,    │ │              │
│              │ │ click-to-edit, undo/redo        │ │              │
│              │ └─────────────────────────────────┘ │              │
└──────────────┴─────────────────────────────────────┴──────────────┘
```

## What you get

- **Four engines in one app.** Postgres, MySQL, SQLite and Redis — all speaking the raw wire protocol in pure Swift, with a typed data model instead of string soup.
- **A clean, simple, powerful editor.** Syntax highlighting, line numbers, ⌘⏎ to run the selection, and tabs that switch instantly.
- **Scalable, exportable, editable results** Streamed grids that stay fast on millions of rows, sort and filter, click-to-edit cells backed by a transactional UPDATE — with undo/redo.
- **Click to Explain** Plan trees for Postgres, MySQL, and SQLite, parsed into a tidy expandable view.
- **Data in, data out.** CSV/JSON export, CSV import with column mapping, query history, saved queries.
- **Connections that just work.** Save profiles with passwords stored in an encrypted vault, tunnel through SSH when you need to, and paste a `postgres://` URL to auto-fill the form.
- **Built for macOS 26.** Liquid Glass, smooth interactions, dark/light theme. 

## Try it

```sh
Scripts/build.sh        # builds build/SexiQL.app (swiftc + sips + codesign)
open build/SexiQL.app
```

Only `xcode-select --install` (Command Line Tools) is required. On Xcode machines, `Scripts/bootstrap.sh` regenerates `SexiQL.xcodeproj` from `project.yml` via XcodeGen.

## For contributors

```sh
Scripts/test.sh         # compiles and runs every package test suite
Scripts/typecheck.sh    # fast typecheck of everything, no binaries
```

Tests are plain XCTest and run unchanged under `swift test`/Xcode; `Scripts/test.sh` uses a bundled XCTest-compatible runtime so no Xcode is needed. Optional live integration tests against real servers:

```sh
SEXIQL_TEST_PG_URL=postgres://user:password@localhost:5432/db Scripts/test.sh
SEXIQL_TEST_MYSQL_URL=mysql://user:password@localhost:3306/db Scripts/test.sh
```

These exercise real handshakes (SCRAM-SHA-256, MD5, cleartext), TLS negotiation, prepared statements, and row streaming. The default suite never starts a database and never invokes psql/mysql/Docker.

The driver layer is a small, clean API:

```swift
let connection = try await manager.connect(profile)

let result = try await connection.execute(
    "SELECT name, score FROM users WHERE id = $1",
    parameters: [.int(42)]            // typed SQLValue — never interpolated
)
for row in result.rows {
    print(row.values[0])              // .string("ada") — typed, not text
}
```

## Layout

```
App/             macOS app target: entry point, chrome, assets, entitlements
Packages/
  SQLCore        profiles, encrypted credential vault, workspace persistence
  SQLDrivers     SQLite + Postgres + MySQL wire drivers, connection manager
  SQLTunnel      system OpenSSH local port forwarding
  SQLEditor      SQL lexer + TextKit 2 editor (highlighting, line numbers)
  SQLGrid        streamed, virtualized result grid
  SQLImportExport  CSV/JSON export, CSV import
  SQLExplainer   EXPLAIN parsing for Postgres/MySQL/SQLite
  SQLUI          SwiftUI glass chrome components
Scripts/         build, test, typecheck, icons, headless UI probe
```

## Design Decisions

- **Credentials** live in an AES-GCM vault under Application Support — never in the workspace file, and never in the login keychain, which would nag you on every rebuild.
- **Postgres TLS** mirrors libpq: SSLRequest → in-place upgrade on the same socket (RDS-compatible); `verify-full` checks the certificate chain and hostname.
- **SSH tunnels** use `/usr/bin/ssh` with argv-only launching, `BatchMode`, `ExitOnForwardFailure`, and a dynamically allocated local port. Key or agent auth only — password auth is intentionally disabled until an audited askpass flow exists.
- **Cell edits** are PK-detected, transactional (BEGIN/COMMIT + rollback), parameterized UPDATEs with undo/redo.
- **Headless verification**: `Scripts/ui_probe.sh` renders the real UI, screenshots + OCRs it, and drives edit/undo/import end-to-end.
