// Encodes provider multipart requests with ordered fields and a final audio file part.

import Foundation

struct MultipartForm {
  let boundary: String
  let body: Data

  init(
    fields: [(String, String)],
    fileField: String,
    fileURL: URL,
    mimeType: String
  ) throws {
    boundary = "Boundary-\(UUID().uuidString)"
    var body = Data()

    for (name, value) in fields {
      body.appendString("--\(boundary)\r\n")
      body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      body.appendString("\(value)\r\n")
    }

    let filename = fileURL.lastPathComponent
    body.appendString("--\(boundary)\r\n")
    body.appendString(
      "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
    body.appendString("Content-Type: \(mimeType)\r\n\r\n")
    body.append(try Data(contentsOf: fileURL))
    body.appendString("\r\n")
    body.appendString("--\(boundary)--\r\n")

    self.body = body
  }
}

extension Data {
  mutating func appendString(_ string: String) {
    append(Data(string.utf8))
  }
}
