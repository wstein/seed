import java.util.*;
import org.antlr.v4.runtime.*;

public class LexDump {
    public static void main(String[] args) throws Exception {
        String grammar = args[0];
        String input = new String(System.in.readAllBytes());
        Lexer lexer = switch (grammar) {
            case "hello" -> new HelloLexer(CharStreams.fromString(input));
            case "expr" -> new ExprLexer(CharStreams.fromString(input));
            case "cover" -> new CoverLexer(CharStreams.fromString(input));
            default -> throw new IllegalArgumentException(grammar);
        };
        lexer.removeErrorListeners();
        StringBuilder sb = new StringBuilder("[\n");
        boolean first = true;
        while (true) {
            Token t = lexer.nextToken();
            if (!first) sb.append(",\n");
            first = false;
            String text = t.getText() == null ? null : t.getText();
            sb.append("  {\"type\": ").append(t.getType())
              .append(", \"text\": ").append(json(text))
              .append(", \"line\": ").append(t.getLine())
              .append(", \"column\": ").append(t.getCharPositionInLine())
              .append(", \"start\": ").append(t.getStartIndex())
              .append(", \"stop\": ").append(t.getStopIndex())
              .append(", \"channel\": ").append(t.getChannel())
              .append("}");
            if (t.getType() == Token.EOF) break;
        }
        sb.append("\n]\n");
        System.out.print(sb);
    }
    static String json(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                default -> b.append(c);
            }
        }
        return b.append("\"").toString();
    }
}
