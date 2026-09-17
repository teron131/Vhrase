// Verifies polishing policy is sent as a system message and editable source remains user content.

import Foundation

@main
struct LLMAdjustmentRequestCheck {
  static func main() throws {
    let data = try LLMAdjustmentClient.requestBody(
      systemInstruction: "SYSTEM CONTRACT",
      userText: "Transcript:\nSOURCE TEXT",
      screenshotDataURL: "data:image/png;base64,AAAA",
      model: "provider/model"
    )
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let messages = root["messages"] as! [[String: Any]]
    precondition(messages.count == 2)
    precondition(messages[0]["role"] as? String == "system")
    precondition(messages[1]["role"] as? String == "user")

    let systemContent = messages[0]["content"] as! [[String: Any]]
    let userContent = messages[1]["content"] as! [[String: Any]]
    precondition(systemContent.count == 1)
    precondition(systemContent[0]["text"] as? String == "SYSTEM CONTRACT")
    precondition(!String(describing: systemContent).contains("SOURCE TEXT"))
    precondition(userContent.count == 2)
    precondition(userContent[0]["type"] as? String == "image_url")
    precondition(userContent[1]["text"] as? String == "Transcript:\nSOURCE TEXT")
    print("LLM adjustment request ok")
  }
}
