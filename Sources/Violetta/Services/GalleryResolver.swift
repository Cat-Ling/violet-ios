import Foundation
import JavaScriptCore

/// Resolves hitomi gallery IDs into image URLs by fetching and evaluating
/// the CDN routing scripts (gg.js + V3 model) in JavaScriptCore.
///
/// This mirrors the server's `gallery-resolver.ts` and `fast-dl/resolver.go`,
/// allowing the iOS app to resolve galleries directly when the server's
/// datacenter IP is blocked by the CDN.
actor GalleryResolver {
    static let shared = GalleryResolver()
    
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    private let ggJSURL = "https://ltn.gold-usergeneratedcontent.net/gg.js"
    
    /// Cached prepared script (V3 model with gg.m/gg.b/gg.s substituted)
    private var scriptCache: String?
    private var scriptCachedAt: Date?
    private let cacheTTL: TimeInterval = 30 * 60 // 30 minutes
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Resolve a gallery ID into an ImageList (urls, bigThumbnails, smallThumbnails).
    func resolve(galleryId: Int) async throws -> ImageList {
        let script = try await ensureScript()
        
        guard let context = JSContext() else {
            throw GalleryResolverError.jsContextFailed
        }
        
        // Suppress JS exceptions as Swift errors
        context.exceptionHandler = { _, exception in
            if let msg = exception?.toString() {
                print("[GalleryResolver] JS exception: \(msg)")
            }
        }
        
        // Evaluate the prepared V3 model script (with gg values baked in)
        context.evaluateScript(script)
        
        // Get the download URL for gallery info
        guard let downloadURLValue = context.evaluateScript("create_download_url('\(galleryId)')"),
              let downloadURL = downloadURLValue.toString(), !downloadURL.isEmpty, downloadURL != "undefined" else {
            throw GalleryResolverError.scriptEvalFailed("create_download_url returned nil")
        }
        
        // Get headers for the gallery info request
        guard let headersValue = context.evaluateScript("hitomi_get_header_content('\(galleryId)')"),
              let headersJSON = headersValue.toString(), !headersJSON.isEmpty, headersJSON != "undefined",
              let headersData = headersJSON.data(using: .utf8),
              let headers = try? JSONSerialization.jsonObject(with: headersData) as? [String: String] else {
            throw GalleryResolverError.scriptEvalFailed("hitomi_get_header_content returned nil")
        }
        
        // Fetch gallery info JS
        var mergedHeaders = headers
        mergedHeaders["User-Agent"] = userAgent
        let galleryInfo = try await fetchText(url: downloadURL, headers: mergedHeaders)
        
        // Evaluate gallery info in the same context (sets `galleryinfo` global)
        context.evaluateScript(galleryInfo)
        
        // Extract image list
        guard let resultValue = context.evaluateScript("hitomi_get_image_list()"),
              let resultJSON = resultValue.toString(), !resultJSON.isEmpty, resultJSON != "undefined",
              let resultData = resultJSON.data(using: .utf8) else {
            throw GalleryResolverError.scriptEvalFailed("hitomi_get_image_list returned nil")
        }
        
        struct RawResult: Decodable {
            let result: [String]
            let btresult: [String]
            let stresult: [String]
        }
        
        let raw = try JSONDecoder().decode(RawResult.self, from: resultData)
        guard !raw.result.isEmpty else {
            throw GalleryResolverError.emptyResult(galleryId)
        }
        
        return ImageList(urls: raw.result, bigThumbnails: raw.btresult, smallThumbnails: raw.stresult)
    }
    
    // MARK: - Script Management
    
    /// Ensures the V3 model script is cached and fresh (re-fetches gg.js if stale).
    private func ensureScript() async throws -> String {
        if let cached = scriptCache, let cachedAt = scriptCachedAt,
           Date().timeIntervalSince(cachedAt) < cacheTTL {
            return cached
        }
        
        // Fetch gg.js and parse it
        let ggBody = try await fetchText(url: ggJSURL, headers: ["User-Agent": userAgent])
        let gg = try parseGg(body: ggBody)
        
        // Substitute placeholders in the V3 model script
        var script = Self.v3ModelScript
        script = script.replacingOccurrences(of: "%%gg.m%", with: gg.m)
        script = script.replacingOccurrences(of: "%%gg.b%", with: gg.b)
        script = script.replacingOccurrences(of: "%%gg.s%", with: gg.s)
        
        scriptCache = script
        scriptCachedAt = Date()
        return script
    }
    
    // MARK: - gg.js Parsing
    
    private struct GgParts {
        let m: String  // comma-separated CDN mapping array
        let b: String  // base path
        let s: String  // hash function body
    }
    
    /// Parses gg.js by evaluating it in a throwaway JSContext and extracting gg.m, gg.b, gg.s.
    private func parseGg(body: String) throws -> GgParts {
        guard let context = JSContext() else {
            throw GalleryResolverError.jsContextFailed
        }
        
        // Strip 'use strict' — it prevents gg resolution in the sandbox
        let code: String
        if let range = body.range(of: "'use strict';") {
            code = String(body[range.upperBound...])
        } else {
            code = body
        }
        
        context.evaluateScript(code)
        
        // Extract gg.m: evaluate the mapping for 0..4095
        guard let mValue = context.evaluateScript(
            """
            var r = ""; for (var i = 0; i < 4096; i++) { r += gg.m(i).toString() + ","; } r
            """
        ), let m = mValue.toString(), m != "undefined" else {
            throw GalleryResolverError.ggParseFailed("gg.m")
        }
        
        guard let bValue = context.evaluateScript("gg.b"),
              let b = bValue.toString(), b != "undefined" else {
            throw GalleryResolverError.ggParseFailed("gg.b")
        }
        
        guard let sValue = context.evaluateScript("gg.s.toString()"),
              let s = sValue.toString(), s != "undefined" else {
            throw GalleryResolverError.ggParseFailed("gg.s")
        }
        
        return GgParts(m: m, b: b, s: s)
    }
    
    // MARK: - HTTP
    
    private func fetchText(url: String, headers: [String: String]) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw GalleryResolverError.invalidURL(url)
        }
        
        var request = URLRequest(url: requestURL)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GalleryResolverError.httpError(url: url, status: status)
        }
        
        guard let text = String(data: data, encoding: .utf8) else {
            throw GalleryResolverError.invalidEncoding(url)
        }
        
        return text
    }
    
    // MARK: - Embedded V3 Model Script
    // Ported from hitomi.la common.js (2026-03) — same as server's
    // scripts/hitomi_get_image_list_v3_model.js
    
    private static let v3ModelScript = """
    function create_download_url(id) {
      return "https://ltn.gold-usergeneratedcontent.net/galleries/" + id + ".js";
    }

    var domain2 = 'gold-usergeneratedcontent.net';

    var gg_m_arr = [%%gg.m%];
    var gg_b = "%%gg.b%";
    var gg = {
      m: function(g) { return gg_m_arr[g] || 0; },
      s: %%gg.s%,
      b: gg_b
    };

    function subdomain_from_url(url, base, dir) {
      var retval = '';
      if (!base) {
        if (dir === 'webp') {
          retval = 'w';
        } else if (dir === 'avif') {
          retval = 'a';
        }
      }

      var b = 16;
      var r = /\\/[0-9a-f]{61}([0-9a-f]{2})([0-9a-f])/;
      var m = r.exec(url);
      if (!m) {
        return retval;
      }

      var g = parseInt(m[2]+m[1], b);
      if (!isNaN(g)) {
        if (base) {
          retval = String.fromCharCode(97 + gg.m(g)) + base;
        } else {
          retval = retval + (1+gg.m(g));
        }
      }

      return retval;
    }

    function url_from_url(url, base, dir) {
      return url.replace(/\\/\\/..?\\.gold-usergeneratedcontent\\.net\\//, '//'+subdomain_from_url(url, base, dir)+'.'+domain2+'/');
    }

    function full_path_from_hash(hash) {
      return gg.b+gg.s(hash)+'/'+hash;
    }

    function real_full_path_from_hash(hash) {
      return hash.replace(/^.*(..)(.)$/, '$2/$1/'+hash);
    }

    function url_from_hash(galleryid, image, dir, ext) {
      ext = ext || dir || image.name.split('.').pop();
      if (dir === 'webp' || dir === 'avif') {
        dir = '';
      } else {
        dir += '/';
      }
      return 'https://a.'+domain2+'/'+dir+full_path_from_hash(image.hash)+'.'+ext;
    }

    function url_from_url_from_hash(galleryid, image, dir, ext, base) {
      if ('tn' === base) {
        return url_from_url('https://a.'+domain2+'/'+dir+'/'+real_full_path_from_hash(image.hash)+'.'+ext, base);
      }
      return url_from_url(url_from_hash(galleryid, image, dir, ext), base, dir);
    }

    function hitomi_get_image_list() {
      var files = galleryinfo["files"];
      var result = [];
      var btresult = [];
      var stresult = [];

      for (var i = 0; i < files.length; i++) {
        var file = files[i];

        if (file["hasavif"] == 1) {
          result.push(url_from_url_from_hash(galleryinfo["id"], file, 'avif'));
        } else {
          result.push(url_from_url_from_hash(galleryinfo["id"], file, 'webp'));
        }

        if (file["haswebp"] == 1) {
          btresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'webpbigtn', 'webp', 'tn'));
          stresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'webpsmalltn', 'webp', 'tn'));
        } else if (file["hasavif"] == 1) {
          btresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'avifbigtn', 'avif', 'tn'));
          stresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'avifsmalltn', 'avif', 'tn'));
        } else {
          btresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'bigtn', 'jpg', 'tn'));
          stresult.push(url_from_url_from_hash(galleryinfo["id"], file, 'smalltn', 'jpg', 'tn'));
        }
      }

      return JSON.stringify({
        result: result,
        btresult: btresult,
        stresult: stresult
      });
    }

    function hitomi_get_header_content(id) {
      return JSON.stringify({
        'referer': 'https://hitomi.la/reader/' + id + '.html',
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
      });
    }
    """
}

// MARK: - Errors

enum GalleryResolverError: LocalizedError {
    case jsContextFailed
    case scriptEvalFailed(String)
    case ggParseFailed(String)
    case invalidURL(String)
    case httpError(url: String, status: Int)
    case invalidEncoding(String)
    case emptyResult(Int)
    
    var errorDescription: String? {
        switch self {
        case .jsContextFailed:
            return "Failed to create JavaScript context"
        case .scriptEvalFailed(let detail):
            return "Script evaluation failed: \(detail)"
        case .ggParseFailed(let field):
            return "Failed to parse gg.js field: \(field)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .httpError(let url, let status):
            return "HTTP \(status) fetching \(url)"
        case .invalidEncoding(let url):
            return "Invalid encoding in response from \(url)"
        case .emptyResult(let id):
            return "Empty image list for gallery \(id)"
        }
    }
}
