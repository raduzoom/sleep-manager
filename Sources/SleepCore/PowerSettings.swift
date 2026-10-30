public enum PowerSettings {
    /// Reads `SleepDisabled` from `pmset -g` output. Nil when the line is missing.
    public static func sleepDisabled(fromPmsetOutput output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return nil
    }
}
