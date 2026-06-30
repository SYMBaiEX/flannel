//
//  LocalModelManagementServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct LocalModelManagementServiceTests {
    @Test("Ollama pull request uses the native pull endpoint")
    func ollamaPullRequestUsesNativeEndpoint() throws {
        let service = LocalModelManagementService(timeout: 12)

        let request = try service.makeOllamaPullRequest(
            endpoint: " http://localhost:11434 ",
            model: " llama3.1 ",
            stream: true
        )

        #expect(request.url?.absoluteString == "http://localhost:11434/api/pull")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 12)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama3.1")
        #expect(json["stream"] as? Bool == true)
    }

    @Test("Ollama delete request uses the native delete endpoint")
    func ollamaDeleteRequestUsesNativeEndpoint() throws {
        let service = LocalModelManagementService(timeout: 7)

        let request = try service.makeOllamaDeleteRequest(
            endpoint: " http://localhost:11434 ",
            model: " llama3.1 "
        )

        #expect(request.url?.absoluteString == "http://localhost:11434/api/delete")
        #expect(request.httpMethod == "DELETE")
        #expect(request.timeoutInterval == 7)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama3.1")
        #expect(json["stream"] == nil)
    }

    @Test("Ollama show request uses the native model info endpoint")
    func ollamaShowRequestUsesNativeEndpoint() throws {
        let service = LocalModelManagementService(timeout: 9)

        let request = try service.makeOllamaShowRequest(
            endpoint: " http://localhost:11434 ",
            model: " llama3.1 ",
            verbose: true
        )

        #expect(request.url?.absoluteString == "http://localhost:11434/api/show")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 9)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama3.1")
        #expect(json["verbose"] as? Bool == true)
    }

    @Test("Ollama show parser decodes details, capabilities, and mixed metadata")
    func ollamaShowParserDecodesModelInfo() throws {
        let data = Data(
            """
            {
              "modified_at": "2026-06-29T12:00:00Z",
              "modelfile": "FROM llama3.1\\nPARAMETER temperature 0.2",
              "parameters": "temperature 0.2",
              "template": "{{ .Prompt }}",
              "license": "llama license",
              "details": {
                "format": "gguf",
                "family": "llama",
                "parameter_size": "8B",
                "quantization_level": "Q4_K_M"
              },
              "model_info": {
                "llama.context_length": 8192,
                "general.architecture": "llama",
                "tokenizer.ggml.add_bos_token": true,
                "general.tags": ["chat", "local"]
              },
              "capabilities": ["completion", "tools"]
            }
            """.utf8
        )

        let info = try LocalModelManagementService.parseOllamaShowResponse(
            data,
            model: "llama3.1",
            endpoint: "http://localhost:11434"
        )

        #expect(info.model == "llama3.1")
        #expect(info.endpoint == "http://localhost:11434")
        #expect(info.details?.family == "llama")
        #expect(info.details?.parameterSize == "8B")
        #expect(info.details?.quantizationLevel == "Q4_K_M")
        #expect(info.capabilities == ["completion", "tools"])
        #expect(info.parameters == "temperature 0.2")
        #expect(info.template == "{{ .Prompt }}")
        #expect(info.license == "llama license")
        #expect(info.modelInfo["llama.context_length"]?.displayText == "8,192")
        #expect(info.modelInfo["general.architecture"]?.displayText == "llama")
        #expect(info.modelInfo["tokenizer.ggml.add_bos_token"]?.displayText == "true")
        #expect(info.modelInfo["general.tags"]?.displayText == "chat, local")
        #expect(info.summaryPairs.contains { $0.0 == "Family" && $0.1 == "llama" })
        #expect(info.modelInfoPairs.contains { $0.0 == "Llama Context Length" && $0.1 == "8,192" })
    }

    @Test("Ollama pull parser decodes progress and completion updates")
    func ollamaPullParserDecodesProgress() throws {
        let progress = try #require(
            try LocalModelManagementService.parseOllamaPullLine(
                #"{"status":"pulling manifest","digest":"sha256:abc","total":100,"completed":25}"#
            )
        )
        let completed = try #require(
            try LocalModelManagementService.parseOllamaPullLine(
                #"{"status":"success"}"#
            )
        )

        #expect(progress.status == "pulling manifest")
        #expect(progress.digest == "sha256:abc")
        #expect(progress.progressFraction == 0.25)
        #expect(completed.status == "success")
        #expect(completed.progressFraction == nil)
    }

    @Test("Ollama pull request rejects missing model names")
    func ollamaPullRequestRejectsMissingModel() {
        #expect(throws: LocalModelManagementError.missingModelName) {
            _ = try LocalModelManagementService().makeOllamaPullRequest(
                endpoint: "http://localhost:11434",
                model: "   "
            )
        }
    }

    @Test("Ollama delete request rejects missing model names")
    func ollamaDeleteRequestRejectsMissingModel() {
        #expect(throws: LocalModelManagementError.missingModelName) {
            _ = try LocalModelManagementService().makeOllamaDeleteRequest(
                endpoint: "http://localhost:11434",
                model: "   "
            )
        }
    }

    @Test("Ollama show request rejects missing model names")
    func ollamaShowRequestRejectsMissingModel() {
        #expect(throws: LocalModelManagementError.missingModelName) {
            _ = try LocalModelManagementService().makeOllamaShowRequest(
                endpoint: "http://localhost:11434",
                model: "   "
            )
        }
    }

    @Test("Ollama discovery joins running state from ps into tagged models")
    func ollamaDiscoveryJoinsRunningState() throws {
        let tags = Data(
            """
            {
              "models": [
                {
                  "name": "llama3.1",
                  "model": "llama3.1:latest",
                  "modified_at": "2026-06-29T12:00:00Z",
                  "size": 4661224676,
                  "details": {
                    "format": "gguf",
                    "family": "llama",
                    "parameter_size": "8B",
                    "quantization_level": "Q4_K_M"
                  }
                }
              ]
            }
            """.utf8
        )
        let running = Data(
            """
            {
              "models": [
                {
                  "name": "llama3.1:latest",
                  "model": "llama3.1:latest",
                  "size": 4661224676,
                  "digest": "sha256:abc",
                  "expires_at": "2026-06-29T12:05:00Z",
                  "size_vram": 2147483648,
                  "context_length": 8192,
                  "details": {
                    "format": "gguf",
                    "family": "llama",
                    "parameter_size": "8B",
                    "quantization_level": "Q4_K_M"
                  }
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeOllamaDescriptors(
            from: tags,
            runningData: running,
            endpoint: "http://localhost:11434"
        )
        let model = try #require(models.first)

        #expect(model.name == "llama3.1:latest")
        #expect(model.displayName == "llama3.1")
        #expect(model.family == "llama")
        #expect(model.parameterSize == "8B")
        #expect(model.quantization == "Q4_K_M")
        #expect(model.format == "gguf")
        #expect(model.contextWindowTokens == 8192)
        #expect(model.loadedInstanceCount == 1)
        #expect(model.sizeBytes == 4_661_224_676)
        #expect(model.sizeVRAMBytes == 2_147_483_648)
        #expect(model.modifiedAt != nil)
        #expect(model.expiresAt != nil)
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.streaming))
    }

    @Test("LM Studio discovery maps display metadata and embedding-only models")
    func lmStudioDiscoveryMapsMetadataAndEmbeddingModels() throws {
        let data = Data(
            """
            {
              "models": [
                {
                  "type": "llm",
                  "publisher": "google",
                  "key": "google/gemma-4-26b-a4b",
                  "display_name": "Gemma 4 26B A4B",
                  "architecture": "gemma4",
                  "quantization": { "name": "Q4_K_M", "bits_per_weight": 4 },
                  "size_bytes": 17990911801,
                  "params_string": "26B-A4B",
                  "loaded_instances": [
                    {
                      "id": "google/gemma-4-26b-a4b",
                      "config": { "context_length": 4096 }
                    }
                  ],
                  "max_context_length": 262144,
                  "format": "gguf",
                  "capabilities": {
                    "vision": true,
                    "trained_for_tool_use": true,
                    "reasoning": {
                      "allowed_options": ["off", "on"],
                      "default": "on"
                    }
                  },
                  "selected_variant": "google/gemma-4-26b-a4b@q4_k_m"
                },
                {
                  "type": "embedding",
                  "publisher": "nomic",
                  "key": "text-embedding-nomic-embed-text-v1.5",
                  "display_name": "Nomic Embed Text v1.5",
                  "quantization": { "name": "F16", "bits_per_weight": 16 },
                  "size_bytes": 274290560,
                  "loaded_instances": [],
                  "max_context_length": 2048,
                  "format": "gguf"
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeLMStudioDescriptors(
            from: data,
            endpoint: "http://localhost:1234"
        )
        let llm = try #require(models.first(where: { $0.name == "google/gemma-4-26b-a4b" }))
        let embedding = try #require(models.first(where: { $0.name == "text-embedding-nomic-embed-text-v1.5" }))

        #expect(llm.displayName == "Gemma 4 26B A4B")
        #expect(llm.publisher == "google")
        #expect(llm.family == "gemma4")
        #expect(llm.parameterSize == "26B-A4B")
        #expect(llm.quantization == "Q4_K_M")
        #expect(llm.format == "gguf")
        #expect(llm.contextWindowTokens == 4096)
        #expect(llm.loadedInstanceCount == 1)
        #expect(llm.sizeBytes == 17_990_911_801)
        #expect(llm.selectedVariant == "google/gemma-4-26b-a4b@q4_k_m")
        #expect(llm.capabilities.contains(.chat))
        #expect(llm.capabilities.contains(.toolCalling))
        #expect(llm.capabilities.contains(.vision))
        #expect(llm.capabilities.contains(.reasoning))

        #expect(embedding.displayName == "Nomic Embed Text v1.5")
        #expect(embedding.publisher == "nomic")
        #expect(embedding.contextWindowTokens == 2048)
        #expect(embedding.capabilities == [.embeddings, .openAICompatible])
    }

    @Test("LM Studio native discovery tolerates partial loaded instance metadata")
    func lmStudioDiscoveryToleratesPartialLoadedInstanceMetadata() throws {
        let data = Data(
            """
            {
              "models": [
                {
                  "type": "llm",
                  "publisher": "openai-community",
                  "key": "openai/gpt-oss-20b",
                  "display_name": "GPT OSS 20B",
                  "loaded_instances": [
                    {
                      "id": "openai/gpt-oss-20b"
                    }
                  ],
                  "max_context_length": 131072,
                  "format": "gguf"
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeLMStudioDescriptors(
            from: data,
            endpoint: "http://localhost:1234"
        )
        let model = try #require(models.first)

        #expect(model.name == "openai/gpt-oss-20b")
        #expect(model.displayName == "GPT OSS 20B")
        #expect(model.contextWindowTokens == 131072)
        #expect(model.loadedInstanceCount == 1)
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.streaming))
    }

    @Test("LM Studio OpenAI-compatible fallback keeps embedding models out of chat routing")
    func lmStudioOpenAICompatibleFallbackUsesConservativeCapabilities() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "id": "text-embedding-nomic-embed-text-v1.5",
                  "owned_by": "nomic"
                },
                {
                  "id": "google/gemma-3-27b-it",
                  "owned_by": "google"
                }
              ]
            }
            """.utf8
        )

        let models = try LocalProviderDiscoveryService.makeOpenAICompatibleDescriptors(
            from: data,
            endpoint: "http://localhost:1234",
            providerKind: .lmStudio
        )
        let embedding = try #require(models.first(where: { $0.name == "text-embedding-nomic-embed-text-v1.5" }))
        let chat = try #require(models.first(where: { $0.name == "google/gemma-3-27b-it" }))

        #expect(embedding.publisher == "nomic")
        #expect(embedding.capabilities == [.embeddings, .openAICompatible])

        #expect(chat.publisher == "google")
        #expect(chat.capabilities.contains(.chat))
        #expect(chat.capabilities.contains(.streaming))
        #expect(chat.capabilities.contains(.openAICompatible))
        #expect(chat.capabilities.contains(.toolCalling) == false)
        #expect(chat.capabilities.contains(.embeddings) == false)
    }
}
