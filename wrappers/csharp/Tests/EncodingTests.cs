using System;
using System.Linq;
using System.Threading.Tasks;
using Xunit;

namespace TurboToken.Tests
{
    public class EncodingTests
    {
        [Fact]
        public void ListEncodings()
        {
            var names = Registry.ListEncodingNames();
            Assert.Contains("cl100k_base", names);
            Assert.Contains("o200k_base", names);
            Assert.Contains("r50k_base", names);
            Assert.Contains("p50k_base", names);
            Assert.Contains("gpt2", names);
            Assert.Contains("p50k_edit", names);
            Assert.Contains("o200k_harmony", names);
            Assert.Equal(7, names.Count);
        }

        [Fact]
        public void GetEncodingSpec()
        {
            var spec = Registry.GetEncodingSpec("cl100k_base");
            Assert.Equal("cl100k_base", spec.Name);
            Assert.Equal(100277, spec.NVocab);
            Assert.Equal(100257, spec.SpecialTokens["<|endoftext|>"]);
        }

        [Fact]
        public void GetEncodingSpecUnknown()
        {
            Assert.Throws<UnknownEncodingException>(() => Registry.GetEncodingSpec("nonexistent"));
        }

        [Fact]
        public void ModelToEncoding()
        {
            Assert.Equal("o200k_base", Registry.ModelToEncoding("gpt-4o"));
            Assert.Equal("cl100k_base", Registry.ModelToEncoding("gpt-4"));
            Assert.Equal("cl100k_base", Registry.ModelToEncoding("gpt-3.5-turbo"));
            Assert.Equal("r50k_base", Registry.ModelToEncoding("davinci"));
            Assert.Equal("gpt2", Registry.ModelToEncoding("gpt2"));
        }

        [Fact]
        public void ModelToEncodingPrefix()
        {
            Assert.Equal("o200k_base", Registry.ModelToEncoding("gpt-4o-2024-01-01"));
            Assert.Equal("cl100k_base", Registry.ModelToEncoding("gpt-4-turbo-preview"));
            Assert.Equal("o200k_base", Registry.ModelToEncoding("o1-preview"));
        }

        [Fact]
        public void ModelToEncodingUnknown()
        {
            Assert.Throws<UnknownModelException>(() => Registry.ModelToEncoding("totally-unknown-model"));
        }

        [Fact]
        public void Version()
        {
            var version = TurboTokenFacade.Version;
            Assert.False(string.IsNullOrEmpty(version));
        }

        [Fact]
        public async Task EncodeDecodeRoundTrip()
        {
            using var enc = await TurboTokenFacade.GetEncodingAsync("cl100k_base");
            var text = "Hello, world!";
            var tokens = enc.Encode(text);
            Assert.NotEmpty(tokens);
            var decoded = enc.Decode(tokens);
            Assert.Equal(text, decoded);
        }

        [Fact]
        public async Task Count()
        {
            using var enc = await TurboTokenFacade.GetEncodingAsync("cl100k_base");
            var text = "Hello, world!";
            var tokens = enc.Encode(text);
            var count = enc.Count(text);
            Assert.Equal(tokens.Length, count);
        }
    }
}
