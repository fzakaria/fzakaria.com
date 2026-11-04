# frozen_string_literal: true

# A Rouge lexer for MLIR's textual IR, so a ```mlir fence gets highlighted.
#
# Rouge 4.7 ships an `llvm` lexer but nothing for MLIR. Defining a RegexLexer
# subclass with a `tag` registers it with Rouge::Lexer.find, which is how
# kramdown resolves a fence's language, and Jekyll loads every file under
# _plugins before it renders a page.
#
# The rules follow the sigils in the MLIR language reference
# (https://mlir.llvm.org/docs/LangRef/): %value, ^block, @symbol, #attribute
# and !type. Custom assembly formats can put arbitrary bare words between
# those, so any word the rules below do not recognise is left as a plain Name.
require "rouge"

module Rouge
  module Lexers
    class MLIR < RegexLexer
      title "MLIR"
      desc "MLIR textual IR (https://mlir.llvm.org/)"
      tag "mlir"
      filenames "*.mlir"
      mimetypes "text/x-mlir"

      # A bare identifier; `$` and `.` are legal after the first character.
      BARE_ID = /[a-zA-Z_][\w$.]*/

      # A suffix identifier: what follows %, ^, @, # or ! in a name.
      SUFFIX_ID = /(?:\d+|[a-zA-Z_$.\-][\w$.\-]*)/

      # Builtin types that are spelled as bare words.
      BUILTIN_TYPES = Set.new(%w[
        bf16 f16 f32 f64 f80 f128 tf32 f8E4M3FN f8E5M2 index none
        complex memref tensor tuple vector
      ]).freeze

      # Bare words with fixed meaning in the generic syntax and the builtin
      # dialect's attributes.
      KEYWORDS = Set.new(%w[
        affine_map affine_set attributes dense dense_resource loc
        sparse strided to unit
      ]).freeze

      CONSTANTS = Set.new(%w[true false]).freeze

      state :root do
        # Whitespace and // line comments.
        rule %r/\s+/, Text
        rule %r{//.*?$}, Comment::Single

        # Strings, with backslash escapes kept inside the token.
        rule %r/"(?:\\.|[^"\\])*"/, Str::Double

        # %value and %value#N, where #N picks one result of a multi-result op.
        rule %r/%#{SUFFIX_ID}(?:#\d+)?/, Name::Variable

        # ^block labels.
        rule %r/\^#{SUFFIX_ID}/, Name::Label

        # @symbol references, quoted or bare.
        rule %r/@"(?:\\.|[^"\\])*"/, Name::Function
        rule %r/@#{SUFFIX_ID}/, Name::Function

        # #attribute aliases and #dialect.attribute.
        rule %r/##{SUFFIX_ID}/, Name::Attribute

        # !type aliases and !dialect.type.
        rule %r/!#{SUFFIX_ID}/, Keyword::Type

        # Hex literals come before shape dimensions so `0xFF` stays one number.
        # MLIR's own lexer does the same, which is why `tensor<0xf32>` (a
        # zero-length dimension) lexes as hex here too; the real parser
        # re-splits that token and this lexer does not.
        rule %r/0x[0-9a-fA-F]+/, Num::Hex

        # A shape dimension before its `x`, as in tensor<4x?xf32>.
        rule %r/(\d+)(x)(?=[\d?a-zA-Z!])/ do
          groups Num::Integer, Punctuation
        end
        rule %r/(\?)(x)(?=[\d?a-zA-Z!])/, Punctuation

        # Numbers: float, then integer.
        rule %r/[-+]?\d+\.\d*(?:[eE][-+]?\d+)?/, Num::Float
        rule %r/[-+]?\d+/, Num::Integer

        # Integer types: i32, si8, ui64.
        rule %r/(?:[su]?i)\d+\b/, Keyword::Type

        # Bare words. A dotted word is an op name (`arith.addi`,
        # `splice.exec`); the rest are classified by the sets above.
        rule BARE_ID do |m|
          word = m[0]
          if word.include?(".")
            token Keyword
          elsif BUILTIN_TYPES.include?(word)
            token Keyword::Type
          elsif CONSTANTS.include?(word)
            token Keyword::Constant
          elsif KEYWORDS.include?(word)
            token Keyword
          else
            token Name
          end
        end

        # The result arrow, then the remaining single-character punctuation.
        rule %r/->/, Punctuation
        rule %r/[=:,(){}\[\]<>*?+\-]/, Punctuation
      end
    end
  end
end
