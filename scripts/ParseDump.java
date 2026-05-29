import java.util.*;
import java.lang.reflect.*;
import org.antlr.v4.runtime.*;
import org.antlr.v4.runtime.tree.*;

public class ParseDump {
    public static void main(String[] args) throws Exception {
        String grammar = args[0], start = args[1];
        String input = new String(System.in.readAllBytes());
        CharStream cs = CharStreams.fromString(input);
        Lexer lexer = switch (grammar) {
            case "hello" -> new HelloLexer(cs);
            case "expr" -> new ExprLexer(cs);
            default -> throw new IllegalArgumentException(grammar);
        };
        lexer.removeErrorListeners();
        CommonTokenStream tokens = new CommonTokenStream(lexer);
        Parser parser = switch (grammar) {
            case "hello" -> new HelloParser(tokens);
            case "expr" -> new ExprParser(tokens);
            default -> throw new IllegalArgumentException(grammar);
        };
        parser.removeErrorListeners();
        Method m = parser.getClass().getMethod(start);
        ParserRuleContext tree = (ParserRuleContext) m.invoke(parser);
        System.out.println(Trees.toStringTree(tree, Arrays.asList(parser.getRuleNames())));
    }
}
