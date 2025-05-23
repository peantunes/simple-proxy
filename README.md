# SimpleProxy

A lightweight HTTP proxy server written in Swift using SwiftNIO. It supports serving local JSON mocks for matching URL patterns and proxying other requests transparently, with live rule reloading.

## Features

- Serve local JSON files for matching URL patterns (via `Mocks/` directory)
- Wildcard-based rule matching (`*`)
- Proxy all other HTTP requests
- Live rule reloading through the `GET /__reload_rules` endpoint
- (Optional) HTTPS interception using a self-signed root certificate

1. Install certificates in active simulators
    •    You’ll need to:
    •    Generate a local Root Certificate (similar to how Charles Proxy and Proxyman do it).
    •    Install this certificate into the macOS Keychain.
    •    Install the certificate into each active iOS Simulator’s keychain (this is possible via simctl commands or directly modifying simulators’ trust settings).

✅ Tools you’ll use:
    •    security command-line tool
    •    xcrun simctl for simulators

⸻

2. Proxy all HTTP/HTTPS requests/responses
    •    You’ll need to:
    •    Build a local proxy server in Swift.
    •    It will handle both HTTP and HTTPS traffic.
    •    For HTTPS interception (MITM — Man In The Middle), you need to decrypt traffic using your custom Root Certificate.
    •    Forward requests to the real servers, and read/intercept responses.

✅ Tools/libraries you can use:
    •    SwiftNIO — for networking, very powerful and modern.
    •    Alternatively a simpler local server (GCDWebServer if you prefer starting easier).
    •    Implement or use an MITM proxy layer.

⸻

3. Map local responses for URL patterns
    •    You want to:
    •    Define rules like: "*myendpoint/list*" matches any URL with that pattern.
    •    Instead of forwarding to the real server, serve a local JSON file or response.

✅ You can build:
    •    A rule engine based on simple wildcard pattern matching (you don’t need full regex at first unless you want).
    •    Load the local responses from JSON/YAML/Text files.

## Architecture
macOS App (SwiftUI or AppKit)
 ├─ Proxy Engine (SwiftNIO Server)
 │    ├─ Accept client connections (HTTP/HTTPS)
 │    ├─ Decrypt HTTPS using installed Root Cert
 │    ├─ Pattern Match URLs
 │    │    ├─ If matches, serve local response
 │    │    └─ Else, forward to real server
 │    └─ Log request and response
 ├─ Certificate Manager
 │    ├─ Generate Root Cert
 │    ├─ Install to macOS
 │    ├─ Install to active Simulators
 └─ Rules Engine
      ├─ URL pattern matching
      └─ Local response serving

Important challenges to plan for
    •    Handling HTTPS properly (Certificates, Trusts, MITM decryption).
    •    Performance — Simulators generate a lot of small requests.
    •    UI (for rules management, basic logging).

First steps I suggest:
    1.    Start by building a simple HTTP Proxy in Swift (just for HTTP, no HTTPS yet).
    2.    Implement simple pattern matching to serve local files.
    3.    Add Certificate generation + installation to macOS + Simulators.
    4.    Upgrade to HTTPS MITM proxying (more complex, but manageable).
    
## Requirements

- macOS 13.0 or later
- Swift 5.8 or later
- OpenSSL command-line tools (for certificate generation)

## Installation

```bash
git clone https://github.com/<your-username>/simple-proxy.git
cd simple-proxy
swift build --configuration release
```

## Usage

1. Create a `Mocks` directory in the project root and add your JSON mock files. For example:

   ```
   Mocks/
   ├── users.json
   └── api/
       └── posts.json
   ```

   This generates two rules:
   - `/users*` serving `Mocks/users.json`
   - `/api/posts*` serving `Mocks/api/posts.json`

2. Run the proxy:

   ```bash
   swift run SimpleProxy
   ```

   The server listens on `http://localhost:8080` by default.

3. Reload rules at runtime without restarting:

   ```bash
   curl http://localhost:8080/__reload_rules
   ```

4. Configure your system or browser to use `localhost:8080` as the HTTP(S) proxy.

## HTTPS Interception (Optional)

A self-signed root certificate and key have been generated and bundled:

- `certificate.crt` — Public certificate (PEM)
- `private.key` — Private key (PEM)
- `bundle.p12` — PKCS#12 bundle (password: `simpleproxy`)

Import `bundle.p12` (for example, by double-clicking it) into your system keychain and mark it as trusted to enable HTTPS interception.

## Configuration

- Modify `Sources/SimpleProxy/RulesManager.swift` to change the mocks directory path.
- Modify `Sources/SimpleProxy/CertificateManager.swift` to change the certificate name, password, or filename.

## License

Add your project license here.
