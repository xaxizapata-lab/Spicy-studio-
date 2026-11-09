import SwiftUI
import UIKit
import Photos
import AVKit
import AVFoundation
import PhotosUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255.0, green: Double((hex >> 8) & 0xFF) / 255.0, blue: Double(hex & 0xFF) / 255.0, opacity: 1.0)
    }
}

enum Theme {
    static let bg = Color(hex: 0x07060A)
    static let card = Color(hex: 0x16121F)
    static let stroke = Color.white.opacity(0.08)
    static let pink = Color(hex: 0xFF2D6F)
    static let dim = Color.white.opacity(0.55)
    static let accent = LinearGradient(colors: [Color(hex: 0xFF2D6F), Color(hex: 0x8B5CF6)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardFill = LinearGradient(colors: [Color(hex: 0x1B1526), Color(hex: 0x100C18)], startPoint: .top, endPoint: .bottom)
}

enum MediaKind: String, Codable { case image, video }

struct Creation: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var kind: MediaKind
    var prompt: String
    var fileName: String
    var thumbName: String?
    var engine: String
    var createdAt = Date()
}

struct Preset: Identifiable, Hashable {
    let id: String
    let title: String
    let prompt: String
    let hue: Double
}

struct GradioJob {
    var image: Data
    var prompt: String
    var negative: String
    var seconds: Double
    var height: Int
    var width: Int
    var steps: Int
    var seed: Int
}

enum GenError: LocalizedError {
    case message(String)
    case rateLimited(Int)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .rateLimited(let s): return "Limite gratis alcanzado. Espera \(s) s."
        }
    }
}

enum Presets {
    static let positions: [Preset] = [
        .init(id: "bj", title: "Mamada", hue: 0.95, prompt: "POV blowjob, eye contact, tongue out, slow rhythm, wet detail, cinematic close up"),
        .init(id: "deepthroat", title: "Garganta", hue: 0.92, prompt: "deepthroat, POV, hands on hips, intense motion, eyes watering"),
        .init(id: "doggy", title: "Perrito", hue: 0.86, prompt: "doggystyle from behind, hair pull, arched back, bed, bouncing motion"),
        .init(id: "cowgirl", title: "Vaquerita", hue: 0.82, prompt: "cowgirl position, riding on top, hands on chest, hips rolling, slow grind"),
        .init(id: "reverse", title: "Reverse", hue: 0.78, prompt: "reverse cowgirl, back to camera, ass grab, rhythmic bouncing"),
        .init(id: "missionary", title: "Misionero", hue: 0.72, prompt: "missionary position, legs up, intimate eye contact, slow deep strokes"),
        .init(id: "titjob", title: "Rusa", hue: 0.68, prompt: "titjob, breasts pressed together, POV, oiled skin, slow motion"),
        .init(id: "handjob", title: "Paja", hue: 0.64, prompt: "POV handjob, close up, teasing strokes, tongue between lips"),
        .init(id: "facial", title: "Facial", hue: 0.58, prompt: "facial cumshot on face, tongue out, heavy breathing, close up"),
        .init(id: "squirt", title: "Squirt", hue: 0.54, prompt: "squirting orgasm, thighs shaking, sheets soaked, dramatic lighting"),
        .init(id: "anal", title: "Anal", hue: 0.48, prompt: "anal doggystyle, arched spine, oiled skin, slow then fast"),
        .init(id: "spread", title: "Abierta", hue: 0.42, prompt: "lying on back spreading legs, teasing, fingers, soft breathing")
    ]
    static let looks: [Preset] = [
        .init(id: "posing", title: "Posing", hue: 0.12, prompt: "posing for the camera, slow body turn, hair moving, natural light"),
        .init(id: "strip", title: "Desnudandose", hue: 0.16, prompt: "slowly undressing, bra slipping off, teasing smile, bedroom"),
        .init(id: "dance", title: "Bailando", hue: 0.20, prompt: "sensual dancing, hips swaying, neon light, moving camera"),
        .init(id: "mirror", title: "Espejo", hue: 0.26, prompt: "mirror selfie, lingerie, checking herself out, soft bounce"),
        .init(id: "shower", title: "Ducha", hue: 0.30, prompt: "in the shower, water running on skin, steam, wet hair"),
        .init(id: "beach", title: "Playa", hue: 0.34, prompt: "on a beach in a bikini, hair in the wind, golden hour"),
        .init(id: "bed", title: "Cama", hue: 0.38, prompt: "lying on a messy bed in lingerie, stretching, morning light"),
        .init(id: "gym", title: "Gym", hue: 0.44, prompt: "in a sports bra and leggings, gym, sweaty skin, breathing"),
        .init(id: "lingerie", title: "Lenceria", hue: 0.50, prompt: "black lace lingerie, seductive pose, dim lamp light, hotel room"),
        .init(id: "anime", title: "Anime", hue: 0.56, prompt: "anime style, expressive face, fluid motion, pastel light"),
        .init(id: "realistic", title: "Realista", hue: 0.60, prompt: "hyper realistic, natural skin texture, film grain, shallow depth of field"),
        .init(id: "cinematic", title: "Cine", hue: 0.66, prompt: "cinematic lighting, teal and orange, 35mm lens, slow dolly in")
    ]
    static let all: [Preset] = positions + looks
    static let styleSuffix = "photorealistic, 8k, natural skin texture, detailed anatomy, cinematic lighting"
    static let defaultNegative = "blurry, low quality, deformed hands, extra fingers, watermark, text, cartoon, plastic skin"
}

enum EngineMode: String, CaseIterable, Identifiable {
    case auto, spaces, pollinations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatico"
        case .spaces: return "Solo gratis (Spaces)"
        case .pollinations: return "Solo Pollinations"
        }
    }
    var detail: String {
        switch self {
        case .auto: return "Intenta gratis y, si falla, usa Pollinations si hay clave."
        case .spaces: return "Cola publica de Hugging Face. Sin claves."
        case .pollinations: return "Necesita clave gratuita. Rapido, hasta 15 s y con sonido."
        }
    }
}

final class Settings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var engine: EngineMode { didSet { d.set(engine.rawValue, forKey: "engine") } }
    @Published var apiKey: String { didSet { d.set(apiKey, forKey: "apiKey") } }
    @Published var videoModel: String { didSet { d.set(videoModel, forKey: "videoModel") } }
    @Published var seconds: Double { didSet { d.set(seconds, forKey: "seconds") } }
    @Published var negative: String { didSet { d.set(negative, forKey: "negative") } }
    @Published var autoSave: Bool { didSet { d.set(autoSave, forKey: "autoSave") } }
    @Published var customSpace: String { didSet { d.set(customSpace, forKey: "customSpace") } }
    @Published var imageSize: Double { didSet { d.set(imageSize, forKey: "imageSize") } }
    init() {
        engine = EngineMode(rawValue: d.string(forKey: "engine") ?? "") ?? .auto
        apiKey = d.string(forKey: "apiKey") ?? ""
        videoModel = d.string(forKey: "videoModel") ?? "alibaba/wan-2.2-fast"
        seconds = d.object(forKey: "seconds") as? Double ?? 5
        negative = d.string(forKey: "negative") ?? Presets.defaultNegative
        autoSave = d.object(forKey: "autoSave") as? Bool ?? true
        customSpace = d.string(forKey: "customSpace") ?? ""
        imageSize = d.object(forKey: "imageSize") as? Double ?? 1024
    }
    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum MediaStore {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static func url(_ name: String) -> URL { docs.appendingPathComponent(name) }
    static func persist(_ temp: URL, ext: String) throws -> String {
        let name = UUID().uuidString + "." + ext
        let dest = url(name)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: temp, to: dest)
        return name
    }
    static func remove(_ item: Creation) {
        try? FileManager.default.removeItem(at: url(item.fileName))
        if let thumb = item.thumbName { try? FileManager.default.removeItem(at: url(thumb)) }
    }
    static func downscale(_ image: UIImage, maxSide: CGFloat, quality: CGFloat = 0.8) -> Data? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxSide / max(w, h))
        let size = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: quality)
    }
    static func thumbnail(forVideo url: URL) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.2, preferredTimescale: 600), actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
    static func saveToPhotos(fileURL: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw GenError.message("Permiso de Fotos denegado.") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: fileURL, options: nil)
            } completionHandler: { ok, err in
                if ok { cont.resume() } else { cont.resume(throwing: err ?? GenError.message("No se pudo guardar")) }
            }
        }
    }
    static func download(_ remote: URL) async throws -> URL {
        let (tmp, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 { throw GenError.message("Descarga fallida (\(http.statusCode))") }
        return tmp
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [Creation] = []
    private let indexURL = MediaStore.url("library.json")
    init() { load() }
    private func load() {
        guard let data = try? Data(contentsOf: indexURL), let decoded = try? JSONDecoder().decode([Creation].self, from: data) else { return }
        items = decoded
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
    func add(_ item: Creation) { items.insert(item, at: 0); save() }
    func delete(_ item: Creation) { items.removeAll { $0.id == item.id }; MediaStore.remove(item); save() }
    func clearAll() { for i in items { MediaStore.remove(i) }; items = []; save() }
}

final class PollinationsService {
    static let shared = PollinationsService()
    func image(prompt: String, width: Int, height: Int, seed: Int) async throws -> URL {
        let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? prompt
        guard var comps = URLComponents(string: "https://image.pollinations.ai/prompt/" + encoded) else { throw GenError.message("Prompt invalido") }
        comps.queryItems = [
            URLQueryItem(name: "width", value: "\(width)"),
            URLQueryItem(name: "height", value: "\(height)"),
            URLQueryItem(name: "seed", value: "\(seed)"),
            URLQueryItem(name: "nologo", value: "true"),
            URLQueryItem(name: "safe", value: "false")
        ]
        guard let url = comps.url else { throw GenError.message("Prompt invalido") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GenError.message("Sin respuesta") }
        if http.statusCode == 402 { throw GenError.rateLimited(Int(http.value(forHTTPHeaderField: "Retry-After") ?? "45") ?? 45) }
        guard http.statusCode == 200, data.count > 2000 else { throw GenError.message("Pollinations respondio \(http.statusCode)") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: tmp)
        return tmp
    }
    func video(image: Data, prompt: String, model: String, seconds: Double, key: String) async throws -> URL {
        guard let url = URL(string: "https://gen.pollinations.ai/v1/chat/completions") else { throw GenError.message("URL invalida") }
        let dataURI = "data:image/jpeg;base64," + image.base64EncodedString()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "duration": Int(seconds),
            "messages": [["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": dataURI]]
            ]]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GenError.message("Sin respuesta") }
        if http.statusCode == 401 { throw GenError.message("Clave invalida") }
        if http.statusCode == 402 { throw GenError.message("Sin saldo en Pollinations") }
        guard http.statusCode == 200 else { throw GenError.message("Pollinations \(http.statusCode)") }
        var candidate: String?
        if let link = http.value(forHTTPHeaderField: "Link"), let range = link.range(of: "https://[^\">;]+", options: .regularExpression) {
            candidate = String(link[range])
        }
        if candidate == nil,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String,
           let range = content.range(of: "https://[^\\s)\"]+\\.mp4", options: .regularExpression) {
            candidate = String(content[range])
        }
        guard let found = candidate, let remote = URL(string: found) else { throw GenError.message("Sin video en la respuesta") }
        return try await MediaStore.download(remote)
    }
}

final class GradioService {
    static let shared = GradioService()
    let spaces = ["multimodalart/wan2-1-fast", "zerogpu-aoti/wan2-2-fp8da-aoti-faster", "r3gm/wan2-2-fp8da-aoti-preview", "cbensimon/wan2-2-fp8da-aoti-preview2", "makiblek/Wan_2.2_I2V_14B_Custom_Lora_Wow"]
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 900
        cfg.timeoutIntervalForResource = 1800
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()
    private func base(for space: String) -> String {
        "https://" + space.lowercased().replacingOccurrences(of: "/", with: "-") + ".hf.space"
    }
    func video(job: GradioJob, space: String, progress: @escaping (String) -> Void) async throws -> URL {
        let root = base(for: space)
        progress("Conectando...")
        let info = try await fetchInfo(root: root)
        let endpoint = try pickEndpoint(info)
        let parameterList = ((info["named_endpoints"] as? [String: Any])?[endpoint] as? [String: Any])?["parameters"] as? [[String: Any]] ?? []
        progress("Subiendo foto...")
        let uploaded = try await upload(root: root, data: job.image)
        var payload: [Any] = []
        for param in parameterList { payload.append(value(for: param, job: job, root: root, uploaded: uploaded)) }
        progress("Generando...")
        let eventID = try await call(root: root, endpoint: endpoint, payload: payload)
        let result = try await stream(root: root, endpoint: endpoint, eventID: eventID)
        progress("Descargando...")
        guard let remote = extractVideoURL(from: result, root: root) else { throw GenError.message("El Space no devolvio video") }
        return try await MediaStore.download(remote)
    }
    private func fetchInfo(root: String) async throws -> [String: Any] {
        guard let url = URL(string: root + "/gradio_api/info") else { throw GenError.message("Space invalido") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GenError.message("Space no disponible") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GenError.message("Respuesta rara") }
        return json
    }
    private func pickEndpoint(_ info: [String: Any]) throws -> String {
        guard let endpoints = info["named_endpoints"] as? [String: Any] else { throw GenError.message("Space sin API") }
        func hasImage(_ key: String) -> Bool {
            guard let dict = endpoints[key] as? [String: Any], let params = dict["parameters"] as? [[String: Any]] else { return false }
            return params.contains { ($0["component"] as? String) == "Image" }
        }
        for name in ["generate_video", "i2v", "image_to_video", "infer", "predict", "generate", "run"] where endpoints[name] != nil && hasImage(name) { return name }
        for name in endpoints.keys where hasImage(name) { return name }
        throw GenError.message("Space incompatible")
    }
    private func value(for param: [String: Any], job: GradioJob, root: String, uploaded: String) -> Any {
        let name = (param["parameter_name"] as? String ?? "").lowercased()
        let component = param["component"] as? String ?? ""
        let fallback = param["parameter_default"]
        if component == "Image" || component == "Video" {
            return ["path": uploaded, "url": root + "/gradio_api/file=" + uploaded, "orig_name": "photo.jpg", "mime_type": "image/jpeg", "is_stream": false, "meta": ["_type": "gradio.FileData"]] as [String: Any]
        }
        if name.contains("negative") { return job.negative }
        if name.contains("prompt") || name.contains("caption") { return job.prompt }
        if name.contains("duration") || name.contains("seconds") { return job.seconds }
        if name.contains("num_frames") || name.contains("frames") { return 49 }
        if name.contains("fps") { return 16 }
        if name.contains("height") { return job.height }
        if name.contains("width") { return job.width }
        if name.contains("step") { return job.steps }
        if name.contains("guidance") || name.contains("cfg") { return 1.0 }
        if name.contains("random") { return true }
        if name.contains("seed") { return job.seed }
        if let fallback, !(fallback is NSNull) { return fallback }
        if (param["type"] as? [String: Any])?["type"] as? String == "boolean" { return false }
        return ""
    }
    private func upload(root: String, data: Data) async throws -> String {
        let boundary = "----spicy" + UUID().uuidString
        guard let url = URL(string: root + "/gradio_api/upload?upload_id=" + UUID().uuidString) else { throw GenError.message("URL invalida") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"files\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GenError.message("Fallo la subida") }
        if let paths = try? JSONSerialization.jsonObject(with: responseData) as? [String], let first = paths.first { return first }
        if let single = try? JSONSerialization.jsonObject(with: responseData) as? String { return single }
        throw GenError.message("Subida inesperada")
    }
    private func call(root: String, endpoint: String, payload: [Any]) async throws -> String {
        guard let url = URL(string: root + "/gradio_api/call" + endpoint) else { throw GenError.message("URL invalida") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload, "session_hash": UUID().uuidString.replacingOccurrences(of: "-", with: "")])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GenError.message("El Space rechazo la peticion") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let eventID = json["event_id"] as? String else { throw GenError.message("Sin evento") }
        return eventID
    }
    private func stream(root: String, endpoint: String, eventID: String) async throws -> Any {
        guard let url = URL(string: root + "/gradio_api/call" + endpoint + "/" + eventID) else { throw GenError.message("URL invalida") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1500
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GenError.message("Stream rechazado") }
        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.replacingOccurrences(of: "event:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let raw = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
            if event == "error" {
                let readable = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                throw GenError.message(readable.isEmpty ? "Error en el Space" : String(readable.prefix(160)))
            }
            if event == "complete", let parsed = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) { return parsed }
        }
        throw GenError.message("El Space cerro sin resultado")
    }
    private func extractVideoURL(from result: Any, root: String) -> URL? {
        if let dict = result as? [String: Any] {
            if let video = dict["video"], let found = extractVideoURL(from: video, root: root) { return found }
            if let s = dict["url"] as? String, s.contains(".mp4") { return URL(string: s) }
            if let p = dict["path"] as? String, p.contains(".mp4") { return URL(string: root + "/gradio_api/file=" + p) }
            for v in dict.values { if let found = extractVideoURL(from: v, root: root) { return found } }
        }
        if let array = result as? [Any] { for v in array { if let found = extractVideoURL(from: v, root: root) { return found } } }
        if let text = result as? String, text.contains(".mp4"), let range = text.range(of: "https://[^\\s\"]+\\.mp4", options: .regularExpression) {
            return URL(string: String(text[range]))
        }
        return nil
    }
}

@MainActor
final class Generator: ObservableObject {
    @Published var busy = false
    @Published var status = ""
    @Published var errorText: String?
    @Published var lastCreation: Creation?
    func reset() { errorText = nil; status = ""; lastCreation = nil }

    func makeVideo(image: UIImage, prompt: String, settings: Settings, store: Store) async {
        guard !busy else { return }
        reset()
        guard let jpeg = MediaStore.downscale(image, maxSide: 896, quality: 0.85) else { errorText = "No pude leer la foto."; return }
        busy = true
        defer { busy = false }
        var chain: [EngineMode] = []
        switch settings.engine {
        case .spaces: chain = [.spaces]
        case .pollinations: chain = [.pollinations]
        case .auto: chain = settings.hasKey ? [.pollinations, .spaces] : [.spaces]
        }
        var failures: [String] = []
        for engine in chain {
            do {
                let url: URL
                if engine == .pollinations {
                    status = "Pollinations: generando..."
                    url = try await PollinationsService.shared.video(image: jpeg, prompt: prompt, model: settings.videoModel, seconds: settings.seconds, key: settings.apiKey.trimmingCharacters(in: .whitespaces))
                } else {
                    let list = settings.customSpace.isEmpty ? GradioService.shared.spaces : [settings.customSpace] + GradioService.shared.spaces
                    url = try await withSpaces(job: GradioJob(image: jpeg, prompt: prompt, negative: settings.negative, seconds: min(settings.seconds, 2.5), height: 512, width: 768, steps: 6, seed: Int.random(in: 0...2_000_000_000)), spaces: list)
                }
                guard let creation = commit(url: url, prompt: prompt, engine: engine, store: store) else { failures.append("No se pudo guardar"); continue }
                lastCreation = creation
                status = ""
                if settings.autoSave { try? await MediaStore.saveToPhotos(fileURL: MediaStore.url(creation.fileName), isVideo: true) }
                return
            } catch { failures.append(error.localizedDescription) }
        }
        errorText = failures.isEmpty ? "No se pudo generar." : failures.joined(separator: "\n\n")
        status = ""
    }

    private func withSpaces(job: GradioJob, spaces: [String]) async throws -> URL {
        var last: Error = GenError.message("Ningun Space respondio")
        for space in spaces {
            do {
                status = "Cola gratis: \(space.split(separator: "/").last ?? "space")..."
                return try await GradioService.shared.video(job: job, space: space) { [weak self] text in
                    Task { @MainActor in self?.status = text }
                }
            } catch { last = error }
        }
        throw last
    }

    func makeImage(prompt: String, settings: Settings, store: Store) async {
        guard !busy else { return }
        reset()
        busy = true
        defer { busy = false }
        status = "Generando imagen..."
        do {
            let side = Int(settings.imageSize)
            let temp = try await PollinationsService.shared.image(prompt: prompt, width: side, height: Int(Double(side) * 1.5), seed: Int.random(in: 0...2_000_000_000))
            guard let creation = commit(url: temp, prompt: prompt, engine: .pollinations, store: store) else { errorText = "No se pudo guardar"; status = ""; return }
            lastCreation = creation
            status = ""
            if settings.autoSave { try? await MediaStore.saveToPhotos(fileURL: MediaStore.url(creation.fileName), isVideo: false) }
        } catch {
            errorText = error.localizedDescription
            status = ""
        }
    }

    private func commit(url: URL, prompt: String, engine: EngineMode, store: Store) -> Creation? {
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let isVideo = ["mp4", "mov"].contains(ext.lowercased())
        guard let name = try? MediaStore.persist(url, ext: ext) else { return nil }
        var thumbName: String?
        if isVideo, let image = MediaStore.thumbnail(forVideo: MediaStore.url(name)), let data = image.jpegData(compressionQuality: 0.7) {
            let thumb = UUID().uuidString + ".jpg"
            try? data.write(to: MediaStore.url(thumb))
            thumbName = thumb
        }
        let creation = Creation(kind: isVideo ? .video : .image, prompt: prompt, fileName: name, thumbName: thumbName, engine: engine.rawValue)
        store.add(creation)
        return creation
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.bold)
            }
            .font(.system(size: 16))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
            .foregroundStyle(enabled ? Color.white : Theme.dim)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .font(.system(size: 15))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    var selected: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
                .foregroundStyle(selected ? Color.white : Theme.dim)
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.dim)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.pink) }
        }
    }
}

struct ProgressOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(Theme.pink).scaleEffect(1.4)
                Text(text.isEmpty ? "Preparando..." : text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("No cierres la app").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .padding(28).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)).padding(40)
        }
    }
}

struct CreationTile: View {
    let item: Creation
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumb = item.thumbName, let image = UIImage(contentsOfFile: MediaStore.url(thumb).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let image = UIImage(contentsOfFile: MediaStore.url(item.fileName).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.card
            }
            if item.kind == .video {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(7).background(.black.opacity(0.55)).clipShape(Circle()).padding(8)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
    }
}

struct PresetCard: View {
    let preset: Preset
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hue: preset.hue, saturation: 0.7, brightness: 0.55), Color(hue: preset.hue + 0.08, saturation: 0.9, brightness: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            Text(preset.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).padding(12)
        }
        .frame(width: 124, height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: Store
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SPICY").font(.system(size: 13, weight: .heavy)).tracking(5).foregroundStyle(Theme.pink)
                    Text("Tu foto.\nTu escena.").font(.system(size: 34, weight: .black)).foregroundStyle(.white)
                    Text("Sube una foto y animala en segundos. Gratis, sin cuenta.").font(.system(size: 14)).foregroundStyle(Theme.dim)
                }
                .padding(.top, 24)
                row("Posiciones", Presets.positions)
                row("Ambientes", Presets.looks)
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(text: "Tus creaciones", trailing: store.items.isEmpty ? nil : "\(store.items.count)")
                    if store.items.isEmpty {
                        Text("Aun no hay nada. Toca un estilo o ve a Crear.")
                            .font(.system(size: 13)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.items.prefix(6)) { item in
                                NavigationLink(value: item) { CreationTile(item: item) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Preset.self) { CreateVideoView(preset: $0) }
        .navigationDestination(for: Creation.self) { DetailView(item: $0) }
    }
    private func row(_ title: String, _ list: [Preset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: title, trailing: "\(list.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list) { preset in
                        NavigationLink(value: preset) { PresetCard(preset: preset) }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

struct CreateVideoView: View {
    let preset: Preset?
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var store: Store
    @State private var picked: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var selected: Preset?
    @State private var extra = ""
    @State private var showResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhotosPicker(selection: $picked, matching: .images) {
                    ZStack {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill()
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 30, weight: .light))
                                Text("Sube la foto de ella").font(.system(size: 14, weight: .semibold))
                                Text("JPG o PNG, cuerpo completo mejor").font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 330)
                    .background(Theme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke))
                }
                .buttonStyle(.plain)

                SectionHeader(text: "Escena", trailing: selected?.title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Presets.all) { item in
                            Chip(title: item.title, selected: selected?.id == item.id) { selected = item }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()

                TextEditor(text: $extra)
                    .font(.system(size: 14)).frame(height: 84)
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)

                if settings.engine != .spaces {
                    SectionHeader(text: "Duracion", trailing: "\(Int(settings.seconds)) s")
                    Slider(value: $settings.seconds, in: 4...15, step: 1).tint(Theme.pink)
                }

                PrimaryButton(title: generator.busy ? "Generando..." : "Generar video", icon: "sparkles", enabled: photo != nil && !generator.busy && !promptText.isEmpty) {
                    Task {
                        if let photo { await generator.makeVideo(image: photo, prompt: promptText, settings: settings, store: store) }
                    }
                }

                if let error = generator.errorText {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.pink)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(18).padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(preset?.title ?? "Crear video")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selected == nil { selected = preset ?? Presets.positions.first }
            generator.reset()
        }
        .onChange(of: picked) { value in
            guard let value else { return }
            Task {
                if let data = try? await value.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image }
            }
        }
        .overlay { if generator.busy { ProgressOverlay(text: generator.status) } }
        .onChange(of: generator.lastCreation) { value in if value != nil { showResult = true } }
        .sheet(isPresented: $showResult) {
            if let creation = generator.lastCreation { NavigationStack { DetailView(item: creation) } }
        }
    }

    private var promptText: String {
        let base = selected?.prompt ?? ""
        let tail = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = tail.isEmpty ? base : base + ", " + tail
        return full.isEmpty ? "" : full + ", " + Presets.styleSuffix
    }
}

struct CreateImageView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var generator: Generator
    @EnvironmentObject private var store: Store
    @State private var prompt = ""
    @State private var showResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Genera desde texto").font(.system(size: 26, weight: .black)).foregroundStyle(.white).padding(.top, 18)
                Text("Describe la escena. Sirve para crear la foto base y luego animarla.").font(.system(size: 13)).foregroundStyle(Theme.dim)
                TextEditor(text: $prompt)
                    .font(.system(size: 14)).frame(height: 140)
                    .scrollContentBackground(.hidden).padding(12)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                PrimaryButton(title: generator.busy ? "Generando..." : "Generar imagen", icon: "photo.fill", enabled: !prompt.isEmpty && !generator.busy) {
                    Task { await generator.makeImage(prompt: prompt + ", " + Presets.styleSuffix, settings: settings, store: store) }
                }
                if let error = generator.errorText {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.pink).padding(12)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text("Motor gratuito de Pollinations: una imagen cada ~45 s.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .padding(18)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Imagenes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if generator.busy { ProgressOverlay(text: generator.status) } }
        .onAppear { generator.reset() }
        .onChange(of: generator.lastCreation) { value in if value != nil { showResult = true } }
        .sheet(isPresented: $showResult) {
            if let creation = generator.lastCreation { NavigationStack { DetailView(item: creation) } }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: Store
    @State private var filter: MediaKind?
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Chip(title: "Todo", selected: filter == nil) { filter = nil }
                    Chip(title: "Videos", selected: filter == .video) { filter = .video }
                    Chip(title: "Imagenes", selected: filter == .image) { filter = .image }
                }
                .padding(.top, 14)
                if visible.isEmpty {
                    Text("Nada guardado todavia.").font(.system(size: 13)).foregroundStyle(Theme.dim).padding(.top, 30)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(visible) { item in
                            NavigationLink(value: item) { CreationTile(item: item) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Estudio")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Creation.self) { DetailView(item: $0) }
    }
    private var visible: [Creation] {
        guard let filter else { return store.items }
        return store.items.filter { $0.kind == filter }
    }
}

struct DetailView: View {
    let item: Creation
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saved = false
    @State private var errorText: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if item.kind == .video, let player {
                    VideoPlayer(player: player).frame(height: 440).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if let image = UIImage(contentsOfFile: MediaStore.url(item.fileName).path) {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text(item.prompt).font(.system(size: 12)).foregroundStyle(Theme.dim)
                GhostButton(title: saved ? "Guardado" : "Guardar en Fotos", icon: "square.and.arrow.down") {
                    Task {
                        do {
                            try await MediaStore.saveToPhotos(fileURL: MediaStore.url(item.fileName), isVideo: item.kind == .video)
                            saved = true
                        } catch { errorText = error.localizedDescription }
                    }
                }
                if let errorText { Text(errorText).font(.system(size: 12)).foregroundStyle(Theme.pink) }
                GhostButton(title: "Borrar", icon: "trash") { store.delete(item); dismiss() }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(item.kind == .video ? "Video" : "Imagen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if item.kind == .video {
                player = AVPlayer(url: MediaStore.url(item.fileName))
                player?.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var store: Store
    @State private var showWipe = false
    private let models = ["alibaba/wan-2.2-fast", "x-ai/grok-imagine-video-1.5-lite", "bytedance/seedance-2.0-fast", "prunaai/p-video", "alibaba/wan-2.6"]
    var body: some View {
        Form {
            Section("Motor") {
                ForEach(EngineMode.allCases) { mode in
                    Button { settings.engine = mode } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: settings.engine == mode ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(settings.engine == mode ? Theme.pink : Theme.dim)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
                                Text(mode.detail).foregroundStyle(Theme.dim).font(.system(size: 11))
                            }
                        }
                    }
                }
            }
            Section("Pollinations (opcional)") {
                SecureField("sk_...", text: $settings.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Modelo", selection: $settings.videoModel) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                Text("Clave gratis en enter.pollinations.ai/keys").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Section("Calidad") {
                VStack(alignment: .leading) {
                    Text("Tamano de imagen: \(Int(settings.imageSize)) px").font(.system(size: 12))
                    Slider(value: $settings.imageSize, in: 512...1536, step: 128)
                }
                TextField("Prompt negativo", text: $settings.negative, axis: .vertical).font(.system(size: 12))
                Toggle("Guardar en Fotos automaticamente", isOn: $settings.autoSave)
            }
            Section("Space personalizado") {
                TextField("usuario/space", text: $settings.customSpace).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Almacenamiento") {
                HStack { Text("Creaciones"); Spacer(); Text("\(store.items.count)").foregroundStyle(Theme.dim) }
                Button("Borrar todo", role: .destructive) { showWipe = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Borrar todas las creaciones?", isPresented: $showWipe) {
            Button("Borrar todo", role: .destructive) { store.clearAll() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Inicio", systemImage: "flame.fill") }
            NavigationStack { CreateVideoView(preset: nil) }.tabItem { Label("Crear", systemImage: "wand.and.stars") }
            NavigationStack { CreateImageView() }.tabItem { Label("Imagenes", systemImage: "photo.badge.plus") }
            NavigationStack { LibraryView() }.tabItem { Label("Estudio", systemImage: "square.grid.2x2.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.pink)
    }
}

@main
struct SpicyApp: App {
    @StateObject private var store = Store()
    @StateObject private var settings = Settings()
    @StateObject private var generator = Generator()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(generator)
                .preferredColorScheme(.dark)
        }
    }
}
