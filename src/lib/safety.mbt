priv struct SafetyRule {
  patterns : Array[String]
  message : String
  dangerous : Bool
}

fn safety_rules() -> Array[SafetyRule] {
  [
    // Dangerous rules
    {
      patterns: ["rm -rf /", "rm -rf ~", "rm -rf /*"],
      message: "Recursive deletion of critical paths",
      dangerous: true,
    },
    {
      patterns: [":(){ :|:& };:"],
      message: "Fork bomb detected",
      dangerous: true,
    },
    {
      patterns: ["> /dev/sda", "dd if=", "mkfs."],
      message: "Direct disk write operation",
      dangerous: true,
    },
    {
      patterns: ["curl | sh", "curl | bash", "wget | sh", "wget | bash",
                  "| bash", "| sh"],
      message: "Remote script execution via pipe",
      dangerous: true,
    },
    {
      patterns: ["sudo rm", "sudo dd", "sudo mkfs"],
      message: "Destructive command with elevated privileges",
      dangerous: true,
    },
    {
      patterns: ["shutdown", "reboot", "halt", "poweroff"],
      message: "System shutdown or reboot",
      dangerous: true,
    },
    // Warning rules
    {
      patterns: ["sudo "],
      message: "Command requires elevated privileges",
      dangerous: false,
    },
    {
      patterns: ["rm -rf", "rm -r "],
      message: "Recursive deletion",
      dangerous: false,
    },
    {
      patterns: ["chmod 777"],
      message: "Overly permissive file permissions",
      dangerous: false,
    },
    {
      patterns: ["eval ", "exec "],
      message: "Dynamic command execution",
      dangerous: false,
    },
    {
      patterns: ["iptables", "ufw "],
      message: "Firewall configuration change",
      dangerous: false,
    },
  ]
}

pub fn analyze_safety(command : String) -> DangerReport {
  let lower = command.to_lower()
  let warnings : Array[String] = []
  let mut is_dangerous = false
  let rules = safety_rules()
  for rule in rules {
    let mut matched = false
    for pattern in rule.patterns {
      if lower.contains(pattern) {
        matched = true
        break
      }
    }
    if matched {
      warnings.push(rule.message)
      if rule.dangerous {
        is_dangerous = true
      }
    }
  }
  { is_dangerous, warnings }
}

pub fn format_warnings(report : DangerReport) -> String {
  if report.warnings.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  if report.is_dangerous {
    buf.write_string("\u001b[1;31m⛔ DANGEROUS COMMAND DETECTED\u001b[0m\n")
  } else {
    buf.write_string("\u001b[1;33m⚠ Warning: potentially dangerous command\u001b[0m\n")
  }
  for w in report.warnings {
    buf.write_string("  → \{w}\n")
  }
  buf.to_string()
}
