module TurboToken
  module Chat
    ChatMessage = Struct.new(:role, :content, :name, keyword_init: true)

    ChatTemplate = Struct.new(:tokens_per_message, :tokens_per_name,
                              :bos_token_ids, :eos_token_ids, keyword_init: true)

    TEMPLATES = {
      turbotoken_v1: -> (eot) {
        ChatTemplate.new(
          tokens_per_message: 3,
          tokens_per_name: 1,
          bos_token_ids: [],
          eos_token_ids: [eot],
        )
      },
      im_tokens: -> (eot) {
        ChatTemplate.new(
          tokens_per_message: 4,
          tokens_per_name: -1,
          bos_token_ids: [],
          eos_token_ids: [eot],
        )
      },
    }.freeze

    def self.resolve_chat_template(mode, spec)
      eot = spec.special_tokens["<|endoftext|>"] || 0
      builder = TEMPLATES[mode]
      raise Error, "Unknown chat template mode: #{mode.inspect}" unless builder
      builder.call(eot)
    end

    def self.encode_chat(encoding, messages, mode: :turbotoken_v1)
      template = resolve_chat_template(mode, encoding.spec)
      tokens = []

      messages.each do |msg|
        role = msg.is_a?(Hash) ? (msg[:role] || msg["role"]) : msg.role
        content = msg.is_a?(Hash) ? (msg[:content] || msg["content"]) : msg.content
        name = msg.is_a?(Hash) ? (msg[:name] || msg["name"]) : msg.name

        role_tokens = encoding.encode(role.to_s)
        content_tokens = encoding.encode(content.to_s)

        tokens.concat(template.bos_token_ids)
        tokens.concat(role_tokens)
        tokens.concat(content_tokens)

        if name
          name_tokens = encoding.encode(name.to_s)
          tokens.concat(name_tokens)
          tokens.concat(Array.new(template.tokens_per_name, 0))
        end

        tokens.concat(Array.new(template.tokens_per_message, 0))
      end

      tokens.concat(template.eos_token_ids)
      tokens
    end

    def self.count_chat(encoding, messages, **opts)
      encode_chat(encoding, messages, **opts).length
    end
  end
end
