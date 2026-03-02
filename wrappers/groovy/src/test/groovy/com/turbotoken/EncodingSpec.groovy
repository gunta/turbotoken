package com.turbotoken

import spock.lang.Specification
import spock.lang.Unroll

class EncodingSpec extends Specification {

    /* ── Registry tests ──────────────────────────────────────────── */

    def 'listEncodingNames returns all 7 encodings sorted'() {
        when:
        def names = Registry.listEncodingNames()

        then:
        names.size() == 7
        names == names.sort()
        names.contains('o200k_base')
        names.contains('cl100k_base')
        names.contains('p50k_base')
        names.contains('r50k_base')
        names.contains('gpt2')
        names.contains('p50k_edit')
        names.contains('o200k_harmony')
    }

    def 'getEncodingSpec returns correct spec for o200k_base'() {
        when:
        def spec = Registry.getEncodingSpec('o200k_base')

        then:
        spec.name == 'o200k_base'
        spec.nVocab == 200019
        spec.specialTokens['<|endoftext|>'] == 199999
        spec.specialTokens['<|endofprompt|>'] == 200018
    }

    def 'getEncodingSpec returns correct spec for cl100k_base'() {
        when:
        def spec = Registry.getEncodingSpec('cl100k_base')

        then:
        spec.name == 'cl100k_base'
        spec.nVocab == 100277
        spec.specialTokens.size() == 5
        spec.specialTokens['<|endoftext|>'] == 100257
        spec.specialTokens['<|fim_prefix|>'] == 100258
        spec.specialTokens['<|fim_middle|>'] == 100259
        spec.specialTokens['<|fim_suffix|>'] == 100260
        spec.specialTokens['<|endofprompt|>'] == 100276
    }

    def 'getEncodingSpec returns correct spec for p50k_base'() {
        when:
        def spec = Registry.getEncodingSpec('p50k_base')

        then:
        spec.nVocab == 50281
        spec.specialTokens['<|endoftext|>'] == 50256
    }

    def 'getEncodingSpec returns correct spec for r50k_base'() {
        expect:
        Registry.getEncodingSpec('r50k_base').nVocab == 50257
    }

    def 'getEncodingSpec returns correct spec for gpt2'() {
        when:
        def spec = Registry.getEncodingSpec('gpt2')

        then:
        spec.nVocab == 50257
        spec.rankFileUrl.contains('r50k_base')
    }

    def 'getEncodingSpec returns correct spec for p50k_edit'() {
        when:
        def spec = Registry.getEncodingSpec('p50k_edit')

        then:
        spec.nVocab == 50281
        spec.rankFileUrl.contains('p50k_base')
    }

    def 'getEncodingSpec returns correct spec for o200k_harmony'() {
        when:
        def spec = Registry.getEncodingSpec('o200k_harmony')

        then:
        spec.nVocab == 200019
        spec.rankFileUrl.contains('o200k_base')
    }

    def 'getEncodingSpec throws for unknown encoding'() {
        when:
        Registry.getEncodingSpec('nonexistent')

        then:
        thrown(IllegalArgumentException)
    }

    /* ── Model resolution tests ──────────────────────────────────── */

    @Unroll
    def 'modelToEncoding resolves #model to #expected'() {
        expect:
        Registry.modelToEncoding(model) == expected

        where:
        model               | expected
        'gpt-4o'            | 'o200k_base'
        'gpt-4'             | 'cl100k_base'
        'gpt-3.5-turbo'     | 'cl100k_base'
        'text-davinci-003'  | 'p50k_base'
        'davinci'           | 'r50k_base'
        'gpt2'              | 'gpt2'
        'gpt-oss-120b'      | 'o200k_harmony'
    }

    @Unroll
    def 'modelToEncoding resolves prefix #model to #expected'() {
        expect:
        Registry.modelToEncoding(model) == expected

        where:
        model                    | expected
        'gpt-4o-2024-05-13'     | 'o200k_base'
        'gpt-4-0613'            | 'cl100k_base'
        'gpt-3.5-turbo-0125'    | 'cl100k_base'
        'o1-preview'            | 'o200k_base'
        'o3-mini'               | 'o200k_base'
        'gpt-oss-beta'          | 'o200k_harmony'
    }

    @Unroll
    def 'modelToEncoding resolves fine-tune #model to #expected'() {
        expect:
        Registry.modelToEncoding(model) == expected

        where:
        model                      | expected
        'ft:gpt-4o:myorg'          | 'o200k_base'
        'ft:gpt-4:myorg'           | 'cl100k_base'
        'ft:gpt-3.5-turbo:myorg'   | 'cl100k_base'
        'ft:davinci-002:myorg'     | 'cl100k_base'
        'ft:babbage-002:myorg'     | 'cl100k_base'
    }

    def 'modelToEncoding throws for unknown model'() {
        when:
        Registry.modelToEncoding('completely-unknown-model')

        then:
        thrown(IllegalArgumentException)
    }

    /* ── Chat template tests ─────────────────────────────────────── */

    def 'resolve returns correct template for TURBOTOKEN_V1'() {
        when:
        def template = Chat.resolve(Chat.TemplateMode.TURBOTOKEN_V1)

        then:
        template.messagePrefix == '<|im_start|>'
        template.messageSuffix == '<|im_end|>\n'
        template.assistantPrefix == '<|im_start|>assistant\n'
    }

    def 'resolve returns correct template for IM_TOKENS'() {
        when:
        def template = Chat.resolve(Chat.TemplateMode.IM_TOKENS)

        then:
        template.messagePrefix == '<|im_start|>'
        template.messageSuffix == '<|im_end|>\n'
        template.assistantPrefix == '<|im_start|>assistant\n'
    }

    def 'formatMessages formats messages correctly'() {
        given:
        def messages = [
            new Chat.ChatMessage('user', 'hello'),
            new Chat.ChatMessage('assistant', 'hi there')
        ]
        def options = new Chat.ChatOptions(true, Chat.TemplateMode.TURBOTOKEN_V1)

        when:
        def formatted = Chat.formatMessages(messages, options)

        then:
        formatted.contains('<|im_start|>user\nhello<|im_end|>')
        formatted.contains('<|im_start|>assistant\nhi there<|im_end|>')
        formatted.endsWith('<|im_start|>assistant\n')
    }

    def 'formatMessages includes name when present'() {
        given:
        def messages = [new Chat.ChatMessage('user', 'alice', 'hello')]
        def options = new Chat.ChatOptions(true, Chat.TemplateMode.TURBOTOKEN_V1)

        when:
        def formatted = Chat.formatMessages(messages, options)

        then:
        formatted.contains('user name=alice')
    }

    def 'formatMessages omits assistant prime when not requested'() {
        given:
        def messages = [new Chat.ChatMessage('user', 'hello')]
        def options = new Chat.ChatOptions(false, Chat.TemplateMode.TURBOTOKEN_V1)

        when:
        def formatted = Chat.formatMessages(messages, options)

        then:
        !formatted.endsWith('<|im_start|>assistant\n')
    }
}
