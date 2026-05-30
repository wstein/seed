import java.util.*;
import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.tree.*;
import org.antlr.v4.runtime.tree.pattern.*;

/**
 * Compiles a tree pattern and matches it against a parse tree with ANTLR's
 * {@link ParseTreePatternMatcher}, printing a canonical dump that Seed's
 * {@code Seed.TreePatternMatcher} must reproduce byte-for-byte.
 *
 * Usage: java PatternDump <Grammar> <subjectStartRule> <patternRule> <xpath> <pattern>
 * Subject text is read from stdin. Output:
 *
 *   PATTERN <pattern-tree-as-lisp>
 *   <matched-subtree> :: key1=[n1|n2] key2=[n3]      (one line per successful find_all match)
 *
 * Labels are sorted by key; each key's nodes are in binding order, joined by '|'.
 */
public class PatternDump {
    public static void main(String[] args) throws Exception {
        String grammar = args[0], startRule = args[1], patternRule = args[2];
        String xpath = args[3], pattern = args[4];
        String input = new String(System.in.readAllBytes());

        Parser parser = newParser(grammar, input);
        List<String> ruleNames = Arrays.asList(parser.getRuleNames());
        ParserRuleContext tree =
            (ParserRuleContext) parser.getClass().getMethod(startRule).invoke(parser);

        // The matcher takes its own lexer/parser (it mutates their input).
        Lexer mLexer = newLexer(grammar, "");
        Parser mParser = newParser(grammar, "");
        ParseTreePatternMatcher matcher = new ParseTreePatternMatcher(mLexer, mParser);
        ParseTreePattern compiled = matcher.compile(pattern, mParser.getRuleIndex(patternRule));

        StringBuilder sb = new StringBuilder();
        sb.append("PATTERN ").append(Trees.toStringTree(compiled.getPatternTree(), ruleNames)).append("\n");

        for (ParseTreeMatch m : compiled.findAll(tree, xpath)) {
            sb.append(Trees.toStringTree(m.getTree(), ruleNames)).append(" ::");
            Map<String, List<ParseTree>> labels = m.getLabels();
            for (String key : new TreeSet<>(labels.keySet())) {
                StringJoiner nodes = new StringJoiner("|", "[", "]");
                for (ParseTree node : labels.get(key)) {
                    nodes.add(Trees.toStringTree(node, ruleNames));
                }
                sb.append(' ').append(key).append('=').append(nodes);
            }
            sb.append("\n");
        }

        System.out.print(sb);
    }

    private static Lexer newLexer(String grammar, String input) throws Exception {
        Lexer lexer = (Lexer) Class.forName(grammar + "Lexer")
            .getConstructor(CharStream.class).newInstance(CharStreams.fromString(input));
        lexer.removeErrorListeners();
        return lexer;
    }

    private static Parser newParser(String grammar, String input) throws Exception {
        Parser parser = (Parser) parserClass(grammar)
            .getConstructor(TokenStream.class)
            .newInstance(new CommonTokenStream(newLexer(grammar, input)));
        parser.removeErrorListeners();
        return parser;
    }

    private static Class<?> parserClass(String grammar) throws ClassNotFoundException {
        try {
            return Class.forName(grammar + "Parser");
        } catch (ClassNotFoundException e) {
            return Class.forName(grammar);
        }
    }
}
