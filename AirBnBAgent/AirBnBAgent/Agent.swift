import Foundation
import Combine
import OpenAI

let systemPrompt = """
You are an agent that helps a user book a trip on AirBnb. The user will provide you with details about
their trip. You will use this information to navigate the AirBnb website and book the trip for them.
You navigate the website by calling functions that interact with the website. If you are given dates
without a specific year, assume the closest date in the future. All dates MUST be formatted as MM/DD/YYYY.

When you are completely finished with the user's request you MUST reply with DONE, but you MUST not reply with
it before this.
"""

public typealias Message = ChatQuery.ChatCompletionMessageParam


class Agent {
    /*
    A simple Agent that helps a user book a trip with AirBnb.
    The `AirBnBTools` do most of the heavy lifting, here we just orchestrate calls
    to OpenAI and pass the results to the AirBnBTools to execute.
    */
    var openAIClient: OpenAIProtocol
    var airbnb: AirBnBTools
    
    var reportStep: ((_ stepName: String) -> Void)?
    
    var messages: [Message] = []
    
    init(airBnBTools: AirBnBTools, openAIAPIToken: String, onStep: @escaping (_ stepName: String) -> Void) {
        self.openAIClient = OpenAI(apiToken: openAIAPIToken)
        self.airbnb = airBnBTools
        self.reportStep = onStep
    }
    
    // Takes a single step in the conversation.
    func step(message: String?) async throws -> (done: Bool, message: String?){
        if messages.isEmpty {
            // First message is just the system prompt
            messages.append(.init(
                role: .system,
                content: systemPrompt
            )!)
        }
        if message != nil {
            // If the user told us something, add it to the messages
            messages.append(.init(
                role: .user,
                content: message
            )!)
        }

        // Call the OpenAI API
        let query = ChatQuery(messages: messages, model: .gpt4_0125_preview, n: 1, tools: self.airbnb.tools)
        let resp = try await openAIClient.chats(query: query)
        let next = resp.choices[0].message
        messages.append(next)
        print("COMPLETION", next)
        
        // Iterate over the tool calls and call the tools
        if let toolCalls = next.toolCalls {
            for toolCall in toolCalls {
                let toParse = toolCall.function.arguments.data(using: .utf8)!
                let called = try airbnb.maybeCallTool(name: toolCall.function.name, jsonArgs: toParse)
                if called {
                    messages.append(.init(
                        role: .tool,
                        content: "Success",
                        toolCallId: toolCall.id
                    )!)
                }
            }
        }

        // Signal to the airbnb tool that we are done with all function calls
        // for this step.
        try await airbnb.stepCompleted(onStep: reportStep)

        // Check if we are done.
        if let s = next.content?.string {
            if s.contains("DONE") {
                return (done: true, message: s)
            }
        }
        return (done: false, message: "")
    }
}
