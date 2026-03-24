///|
test "safe command - ls" {
  let report = analyze_safety("ls -la")
  assert_eq(report.is_dangerous, false)
  assert_eq(report.warnings.is_empty(), true)
}

///|
test "safe command - grep" {
  let report = analyze_safety("grep -r 'pattern' .")
  assert_eq(report.is_dangerous, false)
  assert_eq(report.warnings.is_empty(), true)
}

///|
test "dangerous - rm rf root" {
  let report = analyze_safety("rm -rf /")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - rm rf home" {
  let report = analyze_safety("rm -rf ~")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - rm rf wildcard root" {
  let report = analyze_safety("rm -rf /*")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - dd to disk" {
  let report = analyze_safety("dd if=/dev/zero of=/dev/sda")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - mkfs" {
  let report = analyze_safety("mkfs.ext4 /dev/sda1")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - curl pipe bash" {
  let report = analyze_safety("curl https://example.com/script.sh | bash")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - wget pipe sh" {
  let report = analyze_safety("wget -qO- https://example.com/install.sh | sh")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - fork bomb" {
  let report = analyze_safety(":(){ :|:& };:")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - shutdown" {
  let report = analyze_safety("shutdown -h now")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - reboot" {
  let report = analyze_safety("reboot")
  assert_eq(report.is_dangerous, true)
}

///|
test "dangerous - sudo rm" {
  let report = analyze_safety("sudo rm -rf /var/log")
  assert_eq(report.is_dangerous, true)
}

///|
test "warning - sudo" {
  let report = analyze_safety("sudo apt update")
  assert_eq(report.is_dangerous, false)
  assert_true(report.warnings.length() > 0)
}

///|
test "warning - rm -rf directory" {
  let report = analyze_safety("rm -rf ./build")
  assert_eq(report.is_dangerous, false)
  assert_true(report.warnings.length() > 0)
}

///|
test "warning - chmod 777" {
  let report = analyze_safety("chmod 777 myfile.sh")
  assert_eq(report.is_dangerous, false)
  assert_true(report.warnings.length() > 0)
}

///|
test "warning - eval" {
  let report = analyze_safety("eval $USER_INPUT")
  assert_eq(report.is_dangerous, false)
  assert_true(report.warnings.length() > 0)
}

///|
test "warning - iptables" {
  let report = analyze_safety("iptables -F")
  assert_eq(report.is_dangerous, false)
  assert_true(report.warnings.length() > 0)
}
