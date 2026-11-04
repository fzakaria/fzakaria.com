# frozen_string_literal: true

# Tests for _plugins/mlir_lexer.rb, the Rouge lexer behind ```mlir fences.
#
# Each test lexes a short MLIR snippet and checks the token type Rouge assigns
# to one piece of it, since the token type picks the colour in
# _sass/syntax.scss.
#
# Run from the checkout root inside `nix develop`:
#   ruby tests/plugins/mlir_lexer_test.rb

require "minitest/autorun"
require "rouge"
require_relative "../../_plugins/mlir_lexer"

class MLIRLexerTest < Minitest::Test
  # The token type of the first token whose text is exactly `value`.
  def token_for(source, value)
    lexer = Rouge::Lexer.find("mlir").new
    found = lexer.lex(source).find { |_token, text| text == value }
    refute_nil found, "no token #{value.inspect} in #{source.inspect}"
    found.first
  end

  # The ```mlir fence tag has to resolve to the lexer, or Rouge falls back to
  # plain text.
  def test_tag_is_registered
    assert_equal Rouge::Lexers::MLIR, Rouge::Lexer.find("mlir")
  end

  # SSA values on both sides of an op, including a result-number suffix.
  def test_ssa_values_are_variables
    source = "%sum = arith.addi %a, %b#1 : i32"
    assert_equal Rouge::Token::Tokens::Name::Variable, token_for(source, "%sum")
    assert_equal Rouge::Token::Tokens::Name::Variable, token_for(source, "%b#1")
  end

  # A dialect-qualified op name is the keyword of the line.
  def test_op_names_are_keywords
    source = "%x = splice.exec \"dd\" at 735(%sandbox_717)"
    assert_equal Rouge::Token::Tokens::Keyword, token_for(source, "splice.exec")
  end

  # Builtin types and `!dialect.type` both read as types.
  def test_types
    source = "%p = llvm.load %q : !llvm.ptr -> f32"
    assert_equal Rouge::Token::Tokens::Keyword::Type, token_for(source, "!llvm.ptr")
    assert_equal Rouge::Token::Tokens::Keyword::Type, token_for(source, "f32")
  end

  # A shape's dimensions are numbers and the `x` between them is punctuation,
  # so `4x?xf32` does not lex as one identifier. Rouge merges adjacent tokens
  # of the same type, so `x?x` comes back as a single punctuation token.
  def test_shaped_type_dimensions
    source = "%t : tensor<4x?xf32>"
    assert_equal Rouge::Token::Tokens::Num::Integer, token_for(source, "4")
    assert_equal Rouge::Token::Tokens::Keyword::Type, token_for(source, "f32")
  end

  # A hex literal stays one number and is not split as a shape dimension.
  def test_hex_literal
    source = "%c = arith.constant 0xFF : i8"
    assert_equal Rouge::Token::Tokens::Num::Hex, token_for(source, "0xFF")
    assert_equal Rouge::Token::Tokens::Keyword::Type, token_for(source, "i8")
  end

  # `#dialect.attr` and `@symbol` references.
  def test_attributes_and_symbols
    source = "func.call @main() {tag = #splice.entry<\"/build\" dir 700>}"
    assert_equal Rouge::Token::Tokens::Name::Attribute, token_for(source, "#splice.entry")
    assert_equal Rouge::Token::Tokens::Name::Function, token_for(source, "@main")
    assert_equal Rouge::Token::Tokens::Literal::String::Double, token_for(source, "\"/build\"")
  end

  # Block labels and line comments.
  def test_block_labels_and_comments
    source = "^bb0(%arg0: i64): // entry block"
    assert_equal Rouge::Token::Tokens::Name::Label, token_for(source, "^bb0")
    assert_equal Rouge::Token::Tokens::Comment::Single, token_for(source, "// entry block")
  end
end
