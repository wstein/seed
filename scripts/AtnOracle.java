import java.nio.file.*;
import java.util.*;
import org.antlr.v4.runtime.atn.*;

public class AtnOracle {
    public static void main(String[] args) throws Exception {
        String name = args[0];
        String csv = new String(Files.readAllBytes(Paths.get(name + ".atn"))).trim();
        String[] parts = csv.split(",");
        int[] data = new int[parts.length];
        for (int i = 0; i < parts.length; i++) data[i] = Integer.parseInt(parts[i].trim());

        ATN atn = new ATNDeserializer().deserialize(data);

        TreeMap<Integer,Integer> stateHist = new TreeMap<>();
        TreeMap<Integer,Integer> transHist = new TreeMap<>();
        for (ATNState s : atn.states) {
            int st = (s == null) ? -1 : s.getStateType();
            stateHist.merge(st, 1, Integer::sum);
            if (s != null) {
                for (int i = 0; i < s.getNumberOfTransitions(); i++) {
                    transHist.merge(s.transition(i).getSerializationType(), 1, Integer::sum);
                }
            }
        }
        StringBuilder sb = new StringBuilder();
        sb.append("{\n");
        sb.append("  \"grammarType\": \"").append(atn.grammarType).append("\",\n");
        sb.append("  \"maxTokenType\": ").append(atn.maxTokenType).append(",\n");
        sb.append("  \"numStates\": ").append(atn.states.size()).append(",\n");
        sb.append("  \"numRules\": ").append(atn.ruleToStartState.length).append(",\n");
        sb.append("  \"numDecisions\": ").append(atn.decisionToState.size()).append(",\n");
        sb.append("  \"numModes\": ").append(atn.modeToStartState.size()).append(",\n");
        sb.append("  \"stateTypeHistogram\": ").append(stateHist).append(",\n");
        sb.append("  \"transitionTypeHistogram\": ").append(transHist).append("\n");
        sb.append("}\n");
        System.out.print(sb);
    }
}
