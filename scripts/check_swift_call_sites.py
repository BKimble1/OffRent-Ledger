#!/usr/bin/env python3
"""Checks call sites against the initialiser and static-function signatures declared here.

Not a Swift compiler. It checks *our own* types against *our own* call sites — the class of error
most likely to lurk in code that has never been compiled: a renamed parameter, a missing required
argument, a label typo. It says nothing about Apple's APIs.

Why it exists: 18,000 lines of this repository's Swift have never been compiled, because the
machine that wrote them had no macOS and no Xcode. The `Domain` layer is compiled and tested by
`swift test`; the app layer is not. The single likeliest defect in never-compiled code that calls
into a compiled library is a stale argument label or a missing argument — and that is exactly
what this catches.

Ambiguity is skipped, never failed. SwiftUI views and property-wrapper structs are skipped
entirely: memberwise-init synthesis around wrappers is subtle enough that any finding there would
be noise rather than signal.

Two behaviours were established empirically, by compiling fixtures with the real Swift compiler
rather than by reasoning about the rules:

  * An Optional `var` with no explicit initial value gets `= nil` in the memberwise initialiser.
  * `var x = value`, with no type annotation, is a memberwise member like any other.

And the checker itself was negative-tested: planting a renamed label and a missing required
argument makes it fail. A checker that has never failed proves nothing.

Exit code 1 on any finding.
"""
import re, pathlib, sys
from collections import defaultdict

ROOTS = ["OffRentLedger", "OffRentShared", "OffRentLedgerWidget", "Tests", "OffRentLedgerTests"]
files = []
for r in ROOTS:
    p = pathlib.Path(r)
    if p.exists():
        files += sorted(p.rglob("*.swift"))

# These make a struct's memberwise initialiser hard to predict. Classes have no memberwise
# initialiser at all, so the same attributes are harmless there — @Model classes are checked.
WRAPPERS = ("@State", "@Query", "@Environment", "@Binding", "@Bindable", "@AppStorage",
            "@FocusState", "@Parameter", "@StateObject")

def strip_comments_and_strings(s):
    s = re.sub(r'"""(.*?)"""', '""', s, flags=re.S)
    s = re.sub(r'#"(?:[^"]|"(?!#))*"#', '""', s)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r"//[^\n]*", "", s)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return s

def split_top_level(text, sep=","):
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        if ch == sep and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return [o.strip() for o in out if o.strip()]

def balanced_slice(s, start):
    depth = 0
    for i in range(start, len(s)):
        if s[i] in "([{": depth += 1
        elif s[i] in ")]}":
            depth -= 1
            if depth == 0:
                return s[start+1:i], i+1
    return None

def has_top_level_default(rest):
    """True when `rest` (the part after `label:`) contains a default-value `=` at depth 0."""
    depth = 0
    i = 0
    while i < len(rest):
        ch = rest[i]
        if ch in "([{<": depth += 1
        elif ch in ")]}>": depth -= 1
        elif ch == "=" and depth == 0:
            prev = rest[i-1] if i else ""
            nxt = rest[i+1] if i + 1 < len(rest) else ""
            if prev not in "=!<>" and nxt != "=":
                return True
        i += 1
    return False

def parse_params(param_text):
    params = []
    for part in split_top_level(param_text):
        m = re.match(r"^\s*(?:@\w+\s+)*([\w`_]+)(?:\s+([\w`]+))?\s*:\s*(.+)$", part, re.S)
        if not m:
            return None
        params.append((m.group(1), has_top_level_default(m.group(3))))
    return params


def arity_fits(count, signatures, trailing):
    """True when `count` positional arguments could satisfy any signature.

    `trailing` only ever *relaxes* the bound. A `{` after a call is usually an if- or guard-body,
    not a trailing closure, and treating it as a definite extra argument produced a page of false
    alarms on `if MoneyMath.isNegative(x) { ... }`.
    """
    for params in signatures:
        lower = len([p for p in params if not p[1]])
        upper = len(params)
        if lower <= count <= upper:
            return True
        if trailing and lower <= count + 1 <= upper:
            return True
    return False

inits = defaultdict(list)
kinds, skip_types, explicit = {}, set(), set()

decl_re = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:public |internal |private |fileprivate |final )*"
    r"(struct|class|enum|actor)[ \t]+(\w+)([^\n{]*)",
    re.M)
# A declaration, not a `.init(` call or an `AttributedString.init` inside a body.
init_decl_re = re.compile(
    r"(?m)^[ \t]*(?:@\w+[ \t]*)*(?:public |internal |private |fileprivate |convenience |required |override |nonisolated )*init\??[ \t]*\(")

for f in files:
    src = strip_comments_and_strings(f.read_text())
    lines_before = src
    for m in decl_re.finditer(src):
        kind, name, tail = m.group(1), m.group(2), m.group(3)
        kinds[name] = kind
        open_idx = src.find("{", m.end())
        if open_idx == -1: continue
        sl = balanced_slice(src, open_idx)
        if not sl: continue
        body = sl[0]

        # SwiftUI views and anything using property wrappers: skip.
        attr_context = src[max(0, m.start()-120):m.start()]
        wrapper_risk = kind == "struct" and (
            any(w in body for w in WRAPPERS) or any(w in attr_context for w in WRAPPERS))
        if (": View" in tail or "View," in tail or ": App" in tail or ": Widget" in tail
                or wrapper_risk):
            skip_types.add(name)
            continue

        for im in init_decl_re.finditer(body):
            isl = balanced_slice(body, im.end()-1)
            if not isl: continue
            params = parse_params(isl[0])
            if params is None: continue
            inits[name].append(params)
            explicit.add(name)

        if kind == "struct" and name not in explicit:
            depth, members = 0, []
            for line in body.splitlines():
                stripped = line.strip()
                if depth == 0 and "{" not in stripped:
                    annotated = re.match(
                        r"^(?:public |private |internal )?(var|let)[ \t]+(\w+)[ \t]*:[ \t]*(.+)$", stripped)
                    inferred = re.match(
                        r"^(?:public |private |internal )?(var|let)[ \t]+(\w+)[ \t]*=[ \t]*(.+)$", stripped)
                    if annotated:
                        keyword, member, type_text = annotated.groups()
                        type_only = type_text.split("=")[0].strip()
                        # An Optional `var` with no explicit initial value is implicitly nil, and
                        # the memberwise initialiser gives it `= nil` too. Verified by compiling.
                        optional_var = keyword == "var" and (
                            type_only.endswith("?") or type_only.startswith("Optional<"))
                        members.append((member, has_top_level_default(type_text) or optional_var))
                    elif inferred:
                        members.append((inferred.group(2), True))
                depth += sum(line.count(c) for c in "{([") - sum(line.count(c) for c in "})]")
                depth = max(depth, 0)
            if members:
                inits[name].append(members)

# Initialisers added in an extension are just as real as ones in the type body.
ext_re = re.compile(r"(?m)^[ \t]*extension[ \t]+([\w.]+)")
for f in files:
    src = strip_comments_and_strings(f.read_text())
    for m in ext_re.finditer(src):
        name = m.group(1).split(".")[-1]
        open_idx = src.find("{", m.end())
        if open_idx == -1: continue
        sl = balanced_slice(src, open_idx)
        if not sl: continue
        for im in init_decl_re.finditer(sl[0]):
            isl = balanced_slice(sl[0], im.end()-1)
            if not isl: continue
            params = parse_params(isl[0])
            if params is None: continue
            inits[name].append(params)

aliases = {}
alias_re = re.compile(r"(?m)^[ \t]*typealias[ \t]+(\w+)[ \t]*=[ \t]*([\w.]+)")
for f in files:
    for m in alias_re.finditer(strip_comments_and_strings(f.read_text())):
        aliases[m.group(1)] = m.group(2).split(".")[-1]
for alias, target in aliases.items():
    if target in inits:
        inits[alias].extend(inits[target])
        kinds.setdefault(alias, kinds.get(target, "class"))

for name in skip_types:
    inits.pop(name, None)

print(f"Parsed {len(kinds)} types. Checking {len(inits)} with initialisers; "
      f"{len(skip_types)} SwiftUI/wrapper types skipped.\n")

problems, skipped = [], 0
for f in files:
    src = strip_comments_and_strings(f.read_text())
    for m in re.finditer(r"(?<![\w.])([A-Z]\w+)[ \t]*\(", src):
        name = m.group(1)
        if name not in inits or kinds.get(name) == "enum":
            continue
        sl = balanced_slice(src, m.end()-1)
        if not sl: continue
        arg_text, after = sl
        args = split_top_level(arg_text)

        labels, positional = [], False
        for a in args:
            lm = re.match(r"^([\w`]+)[ \t]*:(?!:)", a)
            if lm: labels.append(lm.group(1))
            else: positional = True
        trailing = bool(re.match(r"[ \t]*\{", src[after:after+4]))
        if positional:
            skipped += 1
            count = len(args)
            if not arity_fits(count, inits[name], trailing):
                best = max(inits[name], key=len)
                line_no = src[:m.start()].count("\n") + 1
                problems.append((f"{f}:{line_no}", name + " (arity)", [f"{count} args"],
                                 [p[0] for p in best], [p[0] for p in best if not p[1]]))
            continue

        matched = False
        for params in inits[name]:
            plabels = [p[0] for p in params]
            required = [p[0] for p in params if not p[1]]
            if not set(labels).issubset(set(plabels)): continue
            missing = [r for r in required if r not in labels]
            if trailing and len(missing) <= 1: missing = []
            if missing: continue
            order = [plabels.index(l) for l in labels]
            if order != sorted(order): continue
            matched = True
            break
        if not matched:
            best = max(inits[name], key=len)
            line_no = src[:m.start()].count("\n") + 1
            problems.append((f"{f}:{line_no}", name, labels,
                             [p[0] for p in best], [p[0] for p in best if not p[1]]))

# ---- static method calls ---------------------------------------------------------------------
# `RentalRateEngine.estimate(terms:asOf:calendar:)` and friends. The app layer calls into the
# domain constantly; the domain is compiled, but the call sites are not.
static_funcs = defaultdict(list)
func_decl_re = re.compile(
    r"(?m)^[ \t]*(?:@\w+[ \t]*)*(?:public |internal |private |fileprivate |nonisolated )*"
    r"static[ \t]+func[ \t]+(\w+)[ \t]*(?:<[^>]*>)?[ \t]*\(")

for f in files:
    src = strip_comments_and_strings(f.read_text())
    for m in decl_re.finditer(src):
        kind, name = m.group(1), m.group(2)
        open_idx = src.find("{", m.end())
        if open_idx == -1: continue
        sl = balanced_slice(src, open_idx)
        if not sl: continue
        for fm in func_decl_re.finditer(sl[0]):
            fsl = balanced_slice(sl[0], fm.end()-1)
            if not fsl: continue
            params = parse_params(fsl[0])
            if params is None: continue
            static_funcs[(name, fm.group(1))].append(params)
    for m in ext_re.finditer(src):
        name = m.group(1).split(".")[-1]
        open_idx = src.find("{", m.end())
        if open_idx == -1: continue
        sl = balanced_slice(src, open_idx)
        if not sl: continue
        for fm in func_decl_re.finditer(sl[0]):
            fsl = balanced_slice(sl[0], fm.end()-1)
            if not fsl: continue
            params = parse_params(fsl[0])
            if params is None: continue
            static_funcs[(name, fm.group(1))].append(params)

for alias, target in aliases.items():
    for (owner, fn), sigs in list(static_funcs.items()):
        if owner == target:
            static_funcs[(alias, fn)].extend(sigs)

static_problems, static_skipped = [], 0
for f in files:
    src = strip_comments_and_strings(f.read_text())
    for m in re.finditer(r"(?<![\w.])([A-Z]\w+)\.(\w+)[ \t]*\(", src):
        key = (m.group(1), m.group(2))
        if key not in static_funcs:
            continue
        sl = balanced_slice(src, m.end()-1)
        if not sl: continue
        arg_text, after = sl
        labels, positional = [], False
        for a in split_top_level(arg_text):
            lm = re.match(r"^([\w`]+)[ \t]*:(?!:)", a)
            if lm: labels.append(lm.group(1))
            else: positional = True
        trailing = bool(re.match(r"[ \t]*\{", src[after:after+4]))
        if positional:
            static_skipped += 1
            count = len(split_top_level(arg_text))
            if not arity_fits(count, static_funcs[key], trailing):
                best = max(static_funcs[key], key=len)
                line_no = src[:m.start()].count("\n") + 1
                static_problems.append((f"{f}:{line_no}", f"{key[0]}.{key[1]} (arity)",
                                        [f"{count} args"], [p[0] for p in best],
                                        [p[0] for p in best if not p[1]]))
            continue

        matched = False
        for params in static_funcs[key]:
            plabels = [p[0] for p in params]
            required = [p[0] for p in params if not p[1]]
            if not set(labels).issubset(set(plabels)): continue
            missing = [r for r in required if r not in labels]
            if trailing and len(missing) <= 1: missing = []
            if missing: continue
            order = [plabels.index(l) for l in labels]
            if order != sorted(order): continue
            matched = True
            break
        if not matched:
            best = max(static_funcs[key], key=len)
            line_no = src[:m.start()].count("\n") + 1
            static_problems.append((f"{f}:{line_no}", f"{key[0]}.{key[1]}", labels,
                                    [p[0] for p in best], [p[0] for p in best if not p[1]]))

print(f"Call sites skipped (positional args): {skipped} initialiser, {static_skipped} static\n")
print(f"Static functions known: {len(static_funcs)}")
if static_problems:
    print(f"\n{len(static_problems)} possible static-call mismatch(es):\n")
    for loc, name, labels, decl, req in static_problems:
        print(f"  {loc}  {name}({', '.join(labels)})")
        print(f"      declared: {decl}")
        print(f"      required: {req}\n")
else:
    print("No static-call mismatches found.\n")

if not problems:
    print("No initialiser call-site mismatches found.")
else:
    print(f"{len(problems)} possible mismatch(es):\n")
    for loc, name, labels, decl, req in problems:
        print(f"  {loc}  {name}({', '.join(labels)})")
        print(f"      declared: {decl}")
        print(f"      required: {req}\n")


sys.exit(1 if (problems or static_problems) else 0)
