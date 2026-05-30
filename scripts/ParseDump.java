import java.util.*;
import java.lang.reflect.*;
import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.tree.*;

/**
 * Parses stdin with a generated grammar and prints the parse tree as a
 * LISP-style string. Grammar-agnostic: it loads <Grammar>Lexer and the
 * parser (named <Grammar>Parser for a combined grammar, or <Grammar> for a
 * split parser grammar) by reflection and invokes the named start rule.
 *
 * Usage: java ParseDump <GrammarPrefix> <startRule>   (e.g. Expr prog)
 */
public class ParseDump {
    public static void main(String[] args) throws Exception {
        String grammar = args[0], start = args[1];
        String input = new String(System.in.readAllBytes());

        Lexer lexer = (Lexer)
            Class.forName(grammar + "Lexer")
                .getConstructor(CharStream.class)
                .newInstance(CharStreams.fromString(input));
        lexer.removeErrorListeners();

        Parser parser = (Parser)
            parserClass(grammar)
                .getConstructor(TokenStream.class)
                .newInstance(new CommonTokenStream(lexer));
        parser.removeErrorListeners();

        ParserRuleContext tree = (ParserRuleContext) parser.getClass().getMethod(start).invoke(parser);
        System.out.println(Trees.toStringTree(tree, Arrays.asList(parser.getRuleNames())));
    }

    private static Class<?> parserClass(String grammar) throws ClassNotFoundException {
        try {
            return Class.forName(grammar + "Parser");
        } catch (ClassNotFoundException e) {
            return Class.forName(grammar);
        }
    }
}
