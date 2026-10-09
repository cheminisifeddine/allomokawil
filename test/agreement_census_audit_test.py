#!/usr/bin/env python3
"""Pin the logic `tool/agreement_census_audit.py` reasons with -- python, not Dart.

    python3 test/agreement_census_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refused Dart on
this host for four ticks running (552-725 MB available against a 900 MB floor,
the difference held by a hypervisor balloon nothing in this PID namespace owns).
The two red tests this tool measures are **Dart** pins, so they cannot be fixed
here -- but what a tick needs before it edits them is a measurement, and a
measurement does not need a Dart VM. Same reasoning
`test/portfolio_allowance_audit_test.py` records for itself.

**No case here reads the network, and no case reads the REAL tree.** Every case
plants a tree on disk in a temp directory and drives the tool's own functions
against it. That is the only way to test a judgement whose whole subject is a
number that drifts: a test asserting "the tree holds 22" is the same stale
number wearing a test's clothes, and it would go red the next time a feature
lands and tell nobody why.
"""

from __future__ import annotations

import io
import os
import re
import shutil
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tool"))

import agreement_census_audit as aca  # noqa: E402


# The smallest Dart file whose comments the reader will grade. Every plant uses
# this shape, so a case that passes proves the thing it says and not that the
# fixture happened to be convenient.
CALLER = """// A file that calls the helper in real code.
String f(int n) => arabicCounted(n, 'a', two: 'b', few: 'c');
"""

PROSE_ONLY = """// This file never calls the helper:
//     return arabicCounted(3, 'x');
String f() => 'x';
"""


def _drop_bytecode_cache() -> None:
    """Remove `tool/__pycache__` so an edited tool is re-read, not re-served."""
    cache = os.path.join(ROOT, "tool", "__pycache__")
    if os.path.isdir(cache):
        shutil.rmtree(cache, ignore_errors=True)


def write_tree(tmp: str, files: dict) -> str:
    for rel, body in files.items():
        path = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
    return tmp


class ExtractionTests(unittest.TestCase):
    """The tool reads the Dart reader's vocabulary rather than copying it."""

    def test_a_top_level_final_is_found(self):
        pat = aca.extract_regex("final _negated = RegExp(r'never\\s*$', "
                                "caseSensitive: false);", "_negated")
        self.assertTrue(pat.search("  never "))
        # caseSensitive: false must survive extraction, or `NEVER` stops
        # counting as a negation and every quoted counter-example becomes a
        # claim.
        self.assertTrue(pat.search("  NEVER "))

    def test_a_local_final_inside_a_function_is_found(self):
        # Measured on why: the first version of `extract_regex` only matched
        # `final _name = RegExp(`, and `calls` -- the pattern that decides
        # whether a file delegates or merely NAMES the helper -- is declared
        # inside `_routingCensus`, not at top level. The tool answered
        # «UNREADABLE, no pattern named _calls» on a perfectly healthy tree,
        # which is the correct exit code for a genuinely moved vocabulary and
        # the wrong answer here.
        src = ("void f() {\n"
               "  final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
               "}\n")
        pat = aca.extract_regex(src, "calls")
        self.assertTrue(pat.search("  arabicCounted(3, 'x')"))

    def test_adjacent_string_literals_become_one_pattern(self):
        # `RegExp('import' r'\s+["\']...')` is how this file writes a pattern
        # that needs both a non-raw and a raw half.
        src = ("final importRe = RegExp('import' r'\\s+[\"\\x27]([^\"\\x27]+)');\n")
        pat = aca.extract_regex(src, "importRe")
        self.assertTrue(pat.search('import "a/b.dart"'))

    def test_a_regex_named_nothing_is_not_silently_empty(self):
        # The failure mode this tool exists to refuse: answering from a
        # remembered copy. A name that is not there must raise, and the CLI
        # must exit 2 rather than report a number.
        with self.assertRaises(LookupError):
            aca.extract_regex("final _other = RegExp(r'x');", "_absent")

    def test_parens_inside_a_raw_string_do_not_unbalance_the_scan(self):
        # The pattern worth reading is itself full of unbalanced parens --
        # `arabicCount(?:ed)?\s*\(` -- so a blind paren counter ran past the
        # close and reported «RegExp( is unclosed» for a file where every
        # RegExp is closed.
        src = ("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
               "final other = RegExp(r'y');\n")
        pat = aca.extract_regex(src, "calls")
        self.assertTrue(pat.search("arabicCounted("))
        self.assertFalse(pat.search("yy"))


class PinReadingTests(unittest.TestCase):
    """The pins are PARSED, not restated -- that is what stops them rotting."""

    def test_a_pin_is_read_from_the_dart_file(self):
        src = ("void main() { expect(census.direct.length, 20, ...);\n"
               "  expect(census.surface.length, 25, ...); }")
        self.assertEqual(aca.read_pins(src), {"direct": 20, "surface": 25})

    def test_a_pin_with_spaces_around_the_field_is_read(self):
        src = "expect( census.direct.length , 22 , 'why');"
        self.assertEqual(aca.read_pins(src), {"direct": 22})

    def test_a_pin_closed_with_a_semicolon_is_still_a_pin(self):
        # Measured on why: the pin regex demands a comma after the value, and a
        # `dart format` pass on a line too long to fit wraps it --
        #   expect(census.direct.length, 20,
        #   'why');
        # ...or, on the shortest possible form, writes the reason after a
        # semicolon. The mutation battery made the terminator `[,;]` and the
        # whole suite stayed GREEN, which means nothing pins that a pin is
        # terminated by a COMMA specifically: a future reformat that swaps the
        # punctuation would silently un-pin both numbers and this tool would
        # report «no pins found» as agreement rather than as a gap.
        src = "expect(census.direct.length, 20; 'why');"
        self.assertEqual(aca.read_pins(src), {"direct": 20})

    def test_a_number_with_no_terminator_is_not_a_pin(self):
        # The other half, and it is what makes the rule above a rule: the
        # terminator has to be REQUIRED. Without it the reader would match the
        # 20 of `greaterThanOrEqualTo(20)` and invent a pin the file never set.
        self.assertEqual(
            aca.read_pins("expect(census.direct.length, 20)"), {})

    def test_an_unpinned_expectation_is_not_invented(self):
        # The surface pin sits next to `greaterThanOrEqualTo(20)`, which is a
        # FLOOR and not a pin. Reading it as one would report drift every time
        # the surface grew, which is information, not a fault.
        self.assertEqual(aca.read_pins("expect(census.surface.length, "
                                       "greaterThanOrEqualTo(20), 'x');"), {})


class CommentFilterTests(unittest.TestCase):
    """The filter that tells a call site from a worked example."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_a_prose_mention_is_not_a_call_site(self):
        root = write_tree(self.tmp, {
            "lib/a.dart": CALLER, "lib/b.dart": PROSE_ONLY})
        src = "final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');"
        calls = re.compile(src.split("r'")[1].split("'")[0])
        direct = aca.direct_call_sites(root, calls)
        self.assertIn("a.dart", direct)
        self.assertNotIn("b.dart", direct)

    def test_removing_the_filter_is_a_movement_a_count_can_see(self):
        # This is the mutation the `census.direct.length` pin claims to police.
        # With one prose-only file the count DOES move, which is the shape a
        # count pin can see.
        root = write_tree(self.tmp, {
            "lib/a.dart": CALLER, "lib/b.dart": PROSE_ONLY})
        calls = re.compile(r"arabicCount(?:ed)?\s*\(")
        with_filter = aca.direct_call_sites(root, calls)
        without = aca.direct_ignoring_comments(root, calls)
        self.assertEqual(len(without) - len(with_filter), 1)

    def test_build_directory_is_not_part_of_the_tree(self):
        # `build/` holds a copy of the tree that no edit can reach. Counting it
        # would let a stale build output move a pin nobody edited.
        #
        # **The ghost has to sit INSIDE a root, and the first version of this
        # case did not.** It planted `<tmp>/build/lib/ghost.dart` -- a SIBLING
        # of `lib/`, not a child -- and `dart_files` walks `lib` and `test` only,
        # so the file was never visited in the first place and the case stayed
        # green with the exclusion deleted. Measured: the mutation «`build/`
        # no longer skipped» SURVIVED this suite, which is the only reason it
        # is fixed here rather than being noted as a limitation.
        root = write_tree(self.tmp, {
            "lib/a.dart": CALLER, "lib/build/ghost.dart": CALLER})
        calls = re.compile(r"arabicCount(?:ed)?\s*\(")
        direct = aca.direct_call_sites(root, calls)
        self.assertIn("a.dart", direct)
        self.assertNotIn("ghost.dart", direct)

    def test_a_build_directory_one_level_down_is_also_excluded(self):
        # Pruning must stop the DESCENT, not only skip the directory it
        # notices: a `lib/src/build/` holding generated copies is reachable by
        # `os.walk` exactly like `lib/build/`, and checking the pruned
        # directory's own path is not enough if the prune does not happen.
        root = write_tree(self.tmp, {
            "lib/a.dart": CALLER, "lib/src/build/deep.dart": CALLER})
        calls = re.compile(r"arabicCount(?:ed)?\s*\(")
        self.assertNotIn("deep.dart", aca.direct_call_sites(root, calls))


class SurfaceTests(unittest.TestCase):
    """The loose probe, and the blanking it depends on."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_a_quoted_sentence_is_an_exhibit_and_is_not_graded(self):
        root = write_tree(self.tmp, {
            "lib/a.dart": "// «3-10 is the broken plural»\n"})
        probe = re.compile(
            r"(\d+)(?:\s*[-–—]\s*(\d+))?\s+(?:is|are|was|were|takes?|"
            r"counts\s+as|reads\s+as|means?|becomes?)\s+"
            r"(?:(?:the|a|an)\s+)?(broken\s+plural|counted\s+singular|plural|"
            r"dual|singular)", re.I)
        negated = re.compile(r"(never|not|no|wrong|instead of|rather than|but)"
                             r"\s*$", re.I)
        self.assertEqual(aca.loose_surface(root, probe, negated), [])

    def test_a_negated_sentence_is_a_counter_example(self):
        root = write_tree(self.tmp, {
            "lib/a.dart": "// never 3-10 is the broken plural\n"})
        probe = re.compile(
            r"(\d+)(?:\s*[-–—]\s*(\d+))?\s+(?:is|are|was|were|takes?|"
            r"counts\s+as|reads\s+as|means?|becomes?)\s+"
            r"(?:(?:the|a|an)\s+)?(broken\s+plural|counted\s+singular|plural|"
            r"dual|singular)", re.I)
        negated = re.compile(r"(never|not|no|wrong|instead of|rather than|but)"
                             r"\s*$", re.I)
        self.assertEqual(aca.loose_surface(root, probe, negated), [])

    def test_a_live_claim_is_found_with_its_line(self):
        root = write_tree(self.tmp, {
            "lib/a.dart": "// filler\n// 3-10 is the broken plural\n"})
        probe = re.compile(
            r"(\d+)(?:\s*[-–—]\s*(\d+))?\s+(?:is|are|was|were|takes?|"
            r"counts\s+as|reads\s+as|means?|becomes?)\s+"
            r"(?:(?:the|a|an)\s+)?(broken\s+plural|counted\s+singular|plural|"
            r"dual|singular)", re.I)
        negated = re.compile(r"(never|not|no|wrong|instead of|rather than|but)"
                             r"\s*$", re.I)
        hits = aca.loose_surface(root, probe, negated)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], "a.dart")
        self.assertEqual(hits[0][1], 2)


class VerdictTests(unittest.TestCase):
    """The judgement, driven on measured dictionaries."""

    def _m(self, **kw):
        base = {"pins": {"direct": 20, "surface": 25}, "direct": 20,
                "comment_filter_delta": 0, "bare_name_delta": 0,
                "surface_count": 25}
        base.update(kw)
        return base

    def test_agreement_is_quiet(self):
        v = aca.verdict(self._m())
        self.assertEqual(v["drift"], [])

    def test_a_pin_that_no_longer_matches_is_drift(self):
        v = aca.verdict(self._m(direct=22))
        self.assertEqual(len(v["drift"]), 1)
        self.assertEqual(v["drift"][0]["pin"], "direct")
        self.assertEqual(v["drift"][0]["delta"], 2)

    def test_a_pin_naming_an_unmeasured_field_is_reported_not_skipped(self):
        # The file may grow a third pin. A tool that silently ignores a pin it
        # cannot measure stops guarding the moment it matters most.
        m = self._m(pins={"direct": 20, "routed": 300})
        v = aca.verdict(m)
        self.assertEqual(len(v["drift"]), 1)
        self.assertEqual(v["drift"][0]["pin"], "routed")
        self.assertIsNone(v["drift"][0]["measured"])

    def test_a_zero_delta_means_the_count_pin_cannot_see_that_mutation(self):
        # THE finding of this tick, pinned so it cannot be argued away: on the
        # real tree both named mutations move the count by ZERO, so
        # `expect(census.direct.length, 20)` would stay green under either of
        # them. A pin that cannot fail is not a guard.
        v = aca.verdict(self._m())
        self.assertFalse(v["direct_pin_falsifiable_for_comment_filter"])
        self.assertFalse(v["direct_pin_falsifiable_for_bare_name"])

    def test_a_movement_makes_the_count_pin_falsifiable(self):
        v = aca.verdict(self._m(comment_filter_delta=1, bare_name_delta=3))
        self.assertTrue(v["direct_pin_falsifiable_for_comment_filter"])
        self.assertTrue(v["direct_pin_falsifiable_for_bare_name"])


class CliTests(unittest.TestCase):
    """The exit codes, which are the part that survives a scrolled log."""

    def setUp(self):
        # **A stale `__pycache__` once made two of these cases fail for a
        # reason that had nothing to do with the tool.** The mutation battery
        # rewrites `tool/agreement_census_audit.py` in place and runs this
        # suite against each mutant; CPython re-cached the LAST mutant under
        # the module's mtime, and after the battery restored the file the cache
        # kept serving «return 0» where the on-disk source says «return 2».
        # Both refusal cases went red against a source that was correct.
        #
        # So the tool is imported FRESH, by path, with the cache dropped --
        # and the cache is dropped again on the way out, because leaving a
        # mutant cached for the NEXT process is the same bug one run later.
        _drop_bytecode_cache()
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.addCleanup(_drop_bytecode_cache)
        self.dart = os.path.join(self.tmp, aca.DART)

    def _dart(self, body: str, root=None):
        # The root is a parameter because several cases measure a SECOND tree:
        # writing the reader into `self.tmp` and measuring `tmp2` died on
        # FileNotFoundError rather than on the judgement under test.
        path = os.path.join(root or self.tmp, aca.DART)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)

    def _capture(self, root):
        buf = io.StringIO()
        real, sys.stdout = sys.stdout, buf
        try:
            code = aca.main(["--root", root])
        finally:
            sys.stdout = real
        return code, buf.getvalue()

    def test_a_missing_dart_file_is_unreadable(self):
        code, _ = self._capture(self.tmp)
        self.assertEqual(code, 2)

    def test_a_moved_pattern_is_unreadable_not_zero(self):
        # The refusal this tool is built around: answering from a remembered
        # copy after the reader's vocabulary moved.
        self._dart("final _negated = RegExp(r'x');\n")
        code, out = self._capture(self.tmp)
        self.assertEqual(code, 2)
        self.assertIn("UNREADABLE", out)

    def test_drift_exits_one_and_says_which_pin(self):
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 20, 'w'); }\n")
        write_tree(self.tmp, {"lib/a.dart": CALLER,
                              "lib/b.dart": CALLER,
                              "lib/c.dart": CALLER})
        code, out = self._capture(self.tmp)
        self.assertEqual(code, 1)
        self.assertIn("DRIFT", out)
        self.assertIn("direct", out)

    def test_agreement_exits_zero_and_says_so(self):
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 2, 'w'); }\n")
        # TWO files call it: `lib/a.dart` and the planted reader itself, which
        # calls the helper to grade against. Measured: the first version pinned
        # 1 and read the tool's own count back as drift -- it was counting the
        # reader, correctly.
        write_tree(self.tmp, {"lib/a.dart": CALLER})
        code, out = self._capture(self.tmp)
        self.assertEqual(code, 0)
        self.assertIn("every pin agrees", out)

    def test_json_publishes_the_measured_numbers(self):
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 2, 'w'); }\n")
        write_tree(self.tmp, {"lib/a.dart": CALLER})
        buf = io.StringIO()
        real, sys.stdout = sys.stdout, buf
        try:
            code = aca.main(["--root", self.tmp, "--json"])
        finally:
            sys.stdout = real
        self.assertEqual(code, 0)
        self.assertIn('"direct": 2', buf.getvalue())
        self.assertIn('"surface_count"', buf.getvalue())


    def test_a_third_pin_the_tool_cannot_measure_is_reported(self):
        # Measured on why: with `key is None` made unreachable the whole suite
        # stayed GREEN. Nothing drove a pin naming a field this tool does not
        # measure, so the branch that exists precisely to stop a guard from
        # silently covering less had no case at all.
        #
        # The shape that matters is the file GROWING a third pin -- `routed`,
        # say -- after this tool was written. The refusal has to be visible at
        # the CLI, where a tick reads it.
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.routed.length, 300, 'w'); }\n")
        write_tree(self.tmp, {"lib/a.dart": CALLER})
        code, out = self._capture(self.tmp)
        self.assertEqual(code, 1)
        self.assertIn("routed", out)
        self.assertIn("re-measure by hand", out)

    def test_a_json_run_publishes_a_pin_it_could_not_measure(self):
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.routed.length, 300, 'w'); }\n")
        write_tree(self.tmp, {"lib/a.dart": CALLER})
        buf = io.StringIO()
        real, sys.stdout = sys.stdout, buf
        try:
            code = aca.main(["--root", self.tmp, "--json"])
        finally:
            sys.stdout = real
        self.assertEqual(code, 1)
        self.assertIn('"pin": "routed"', buf.getvalue())


    def test_the_comment_filter_delta_is_the_count_the_filter_moved(self):
        # Measured on why: forcing `comment_filter_delta` to a constant 0 left
        # the suite GREEN. Nothing read the field back, so the report could lie
        # about the one thing it exists to say -- that a census reading prose
        # as call sites is currently invisible to a count pin.
        self.tmp2 = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp2)
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 1, 'w'); }\n",
                   root=self.tmp2)
        write_tree(self.tmp2, {"lib/a.dart": CALLER, "lib/b.dart": PROSE_ONLY})
        m = aca.measure(self.tmp2)
        self.assertEqual(m["comment_filter_delta"], 1)
        self.assertIn("b.dart", m["comment_filter_files"])
        self.assertTrue(
            aca.verdict(m)["direct_pin_falsifiable_for_comment_filter"])

    def test_the_bare_name_delta_is_measured_not_asserted(self):
        # The other reported field, and the one whose mutation also survived:
        # widening `calls` to the bare name has to MOVE the number, or the
        # report's "PIN CANNOT SEE IT" is an opinion rather than a measurement.
        self.tmp3 = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp3)
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 1, 'w'); }\n",
                   root=self.tmp3)
        # A file that NAMES the helper without calling it: prose the strict
        # pattern rejects and the bare name accepts.
        # TWO files name the helper without calling it, so the delta is 2.
        # Measured on why the number is 2 and not 1: the case used to plant one
        # and assert 1, and the mutation battery proved that worthless --
        # forcing the field to a constant 1 left the suite GREEN, because 1 is
        # what the case already expected. A case that pins a value the faked
        # arithmetic can produce is not testing the arithmetic. Two names-only
        # files give the measurement a number a constant cannot imitate.
        write_tree(self.tmp3, {
            "lib/a.dart": CALLER,
            "lib/names.dart": "const k = arabicCounted;\n",
            "lib/also_names.dart": "const j = arabicCount;\n"})
        m = aca.measure(self.tmp3)
        self.assertEqual(m["bare_name_delta"], 2)
        self.assertEqual(m["bare_name_files"], ["also_names.dart", "names.dart"])
        self.assertTrue(aca.verdict(m)["direct_pin_falsifiable_for_bare_name"])

    def test_a_tree_with_no_prose_mentions_reports_a_zero_delta(self):
        # The other half: a measurement that is always positive is not a
        # measurement, it is a constant with a good name. Measured here, so the
        # report's "PIN CANNOT SEE IT" verdict on the real tree is backed by a
        # case that shows the zero is COMPUTED rather than defaulted.
        self.tmp4 = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp4)
        self._dart("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                   "final _negated = RegExp(r'never\\s*$', "
                   "caseSensitive: false);\n"
                   "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                   "void main() { expect(census.direct.length, 2, 'w'); }\n",
                   root=self.tmp4)
        write_tree(self.tmp4, {"lib/a.dart": CALLER, "lib/b.dart": CALLER})
        m = aca.measure(self.tmp4)
        self.assertEqual(m["bare_name_delta"], 0)
        self.assertEqual(m["comment_filter_delta"], 0)
        v = aca.verdict(m)
        self.assertFalse(v["direct_pin_falsifiable_for_bare_name"])
        self.assertFalse(v["direct_pin_falsifiable_for_comment_filter"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
