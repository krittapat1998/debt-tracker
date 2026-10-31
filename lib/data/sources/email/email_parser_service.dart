import '../statement_source_parser.dart';

/// Placeholder for parsing bank e-mail statements (e.g. via the Gmail API).
///
/// To add it later:
/// 1. Fetch messages into [RawStatementMessage] with
///    `source: StatementSourceType.email`, `sender` = From, `subject`, and
///    the plain-text body (decrypt PDF statements on device if needed).
/// 2. Implement [parse] with per-bank rules (the SMS config format in
///    `assets/sms_patterns.json` can be reused for subject/body regexes).
/// 3. Register the instance in `statementParsersProvider`
///    (lib/ui/providers.dart). Nothing in the data model or UI changes:
///    the import screen already works on [ParsedStatementEvent].
class EmailParserService implements StatementSourceParser {
  const EmailParserService();

  @override
  StatementSourceType get sourceType => StatementSourceType.email;

  @override
  bool canParse(RawStatementMessage message) => false;

  @override
  ParsedStatementEvent? parse(RawStatementMessage message) => null;
}
