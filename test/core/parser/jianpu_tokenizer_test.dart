import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/parser/jianpu_tokenizer.dart';

void main() {
  const tokenizer = JianpuTokenizer();

  test('records 1-based character columns distinct from tokenIndex', () {
    final tokens = tokenizer.tokenizeLine('3 4 1# 5', 1);

    expect(tokens, hasLength(4));

    expect(tokens[0].text, '3');
    expect(tokens[0].line, 1);
    expect(tokens[0].tokenIndex, 1);
    expect(tokens[0].column, 1);

    expect(tokens[1].text, '4');
    expect(tokens[1].tokenIndex, 2);
    expect(tokens[1].column, 3);

    expect(tokens[2].text, '1#');
    expect(tokens[2].tokenIndex, 3);
    expect(tokens[2].column, 5);
    expect(tokens[2].tokenIndex, isNot(tokens[2].column));

    expect(tokens[3].text, '5');
    expect(tokens[3].tokenIndex, 4);
    expect(tokens[3].column, 8);
  });

  test('keeps tokenIndex at 1 when leading spaces shift the column', () {
    final tokens = tokenizer.tokenizeLine('  1#', 2);

    expect(tokens, hasLength(1));
    expect(tokens.single.text, '1#');
    expect(tokens.single.line, 2);
    expect(tokens.single.tokenIndex, 1);
    expect(tokens.single.column, 3);
  });
}
