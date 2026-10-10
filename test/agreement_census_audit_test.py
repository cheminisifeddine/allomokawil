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
                "combined_delta": 0, "combined_files": [],
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

class MembershipTests(unittest.TestCase):
    """The prescription the 9 Oct tick left for the next tick.

    That tick ordered: «replace the count pin with a membership assertion --
    "the set of claim-bearing files whose only mention of the helper is prose
    is EMPTY"». Two facts measured here make that prescription wrong as
    written, and both are facts about the TREE rather than about the argument:

      * **the assertion already exists.** It is the `directClaimFiles` /
        `isEmpty` pair in the same test, six lines above the count pin. A tick
        that follows the prescription literally writes a second copy of a
        guard that is already there.
      * **and the existing copy is vacuous on this tree too.** Zero files
        mention the helper in prose without calling it, so the set it asserts
        empty is empty for want of input, not because a filter works. Deleting
        the count pin -- which DOES see drift, +2 today -- for that leaves the
        tree with one guard that can fail and one that cannot, where it had
        two that can.

    So the assertions here pin the *measurement* that refutes the
    prescription, and the plant case pins that a membership assertion WOULD
    catch the shape if the tree ever supplied it.
    """

    def _membership_in(self, body: str) -> dict:
        return aca.read_membership(body)

    def test_the_assertion_is_read_from_the_dart_file(self):
        m = self._membership_in(
            "census.direct.intersection(claimFiles).difference({"
            "'a.dart', 'b.dart'});")
        self.assertTrue(m["present"])
        self.assertEqual(m["exempt"], ["a.dart", "b.dart"])

    def test_a_tree_with_no_membership_assertion_reports_it_absent(self):
        # Absent and vacuous are different faults with different fixes, so the
        # reader must be able to tell them apart.
        m = self._membership_in("final directClaimFiles = <String>{};")
        self.assertFalse(m["present"])
        self.assertEqual(m["exempt"], [])

    def test_a_collected_set_that_is_never_asserted_empty_is_not_a_guard(self):
        # The computation without the `isEmpty` is the half that looks like
        # coverage in a diff and catches nothing.
        body = ("census.direct.intersection(claimFiles).difference({'a.dart'});"
                " expect(directClaimFiles, isNotEmpty);")
        m = self._membership_in(body)
        self.assertTrue(m["present"])
        self.assertFalse(m["guarded"])

    def test_the_dart_tree_already_holds_the_assertion_the_tick_would_add(self):
        # The load-bearing one: it is what makes the prescription a duplicate
        # rather than a repair. Reads the REAL file, so it fails the moment the
        # assertion is deleted -- which is the day the prescription becomes
        # correct.
        with open(os.path.join(ROOT, aca.DART), encoding="utf-8") as fh:
            src = fh.read()
        m = aca.read_membership(src)
        self.assertTrue(m["present"],
                        "the membership assertion is GONE -- so replacing the "
                        "count pin with it is now a repair, not a duplicate")
        self.assertTrue(m["guarded"])
        self.assertIn("quote_duration_copy.dart", m["exempt"])

    def test_the_real_tree_supplies_no_prose_only_file_so_it_cannot_fail(self):
        # The finding that refuses the prescription. Counted from the real
        # tree, but NOT asserted as a count -- it is read and reported, because
        # pinning `0` here would be the same stale-number mistake this file
        # exists to correct. The assertion is about the SHAPE: if the tree ever
        # gains such a file, this goes red and the prescription becomes sound.
        calls = aca.extract_regex(
            open(os.path.join(ROOT, aca.DART), encoding="utf-8").read(), "calls")
        prose_only = aca.prose_only_files(ROOT, calls)
        self.assertEqual(
            sorted(prose_only), [],
            "the tree now has prose-only file(s) %s -- a membership assertion "
            "is falsifiable here, so the count pin may be replaced by it"
            % sorted(prose_only))

    def test_a_prose_only_file_is_what_makes_membership_falsifiable(self):
        # The other half: the shape DOES work, on a tree that has the case.
        # Without this the finding above would be read as "membership cannot
        # catch prose" -- the opposite of what it says.
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"lib/caller.dart": CALLER,
                             "lib/prose.dart": PROSE_ONLY})
            calls = aca.extract_regex(
                open(os.path.join(ROOT, aca.DART), encoding="utf-8").read(),
                "calls")
            prose_only = aca.prose_only_files(tmp, calls)
            self.assertEqual(sorted(prose_only), ["prose.dart"])

    def test_the_plant_shape_is_exactly_what_prose_only_looks_for(self):
        # The plant in the Dart file has to carry the parenthesis, and this is
        # why: the call-site pattern requires `(`, so a plant writing a bare
        # name could not tell the two apart however the filter behaved. Same
        # reason, pinned on this side so the fixture cannot quietly change.
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"lib/bare.dart":
                             "// see arabicCounted here\nString f() => 'x';\n"})
            calls = aca.extract_regex(
                open(os.path.join(ROOT, aca.DART), encoding="utf-8").read(),
                "calls")
            self.assertEqual(sorted(aca.prose_only_files(tmp, calls)), [],
                             "a bare-name mention does not match `calls` at "
                             "all -- it is not a case this can ever supply")


class MembershipCliTests(CliTests):
    """The render path, which is where a reader is actually convinced.

    Both cases here exist because the first mutation battery found them
    SURVIVING: `prose_only_count` hardcoded and the VACUOUS sentence softened
    both left the suite green, because every other case drives `verdict()`
    directly and never renders. A judgement that is right in a dict and
    absent from the output has not told anybody anything.
    """

    def test_a_tree_with_no_prose_only_file_says_vacuous(self):
        self._dart(open(os.path.join(ROOT, aca.DART), encoding="utf-8").read())
        write_tree(self.tmp, {"lib/caller.dart": CALLER,
                              "lib/prose.dart": PROSE_ONLY})
        # PROSE_ONLY is the negative shape, so this tree HAS one -- measure it.
        code, out = self._capture(self.tmp)
        self.assertIn("prose-only", out)
        self.assertIn("IS falsifiable here", out)
        self.assertNotIn("VACUOUS HERE", out)

    def test_a_tree_whose_only_caller_has_no_prose_says_vacuous(self):
        self._dart(open(os.path.join(ROOT, aca.DART), encoding="utf-8").read())
        write_tree(self.tmp, {"lib/caller.dart": CALLER})
        code, out = self._capture(self.tmp)
        self.assertIn("VACUOUS HERE", out)
        self.assertIn("prose-only", out)
        # The count that decides it, spelled out -- so a hardcoded `1` cannot
        # render as agreement here.
        self.assertIn("files in this tree that are prose-only : 0", out)


class MembershipVerdictTests(unittest.TestCase):
    """`verdict()` must answer the prescription question, not just count."""

    def _v(self, **over):
        base = {"membership_present": True, "membership_guarded": True,
                "prose_only": [], "prose_only_count": 0}
        base.update(over)
        m = {"pins": {"direct": 22}, "direct": 22, "direct_files": [],
             "comment_filter_delta": 0, "comment_filter_files": [],
             "bare_name_delta": 0, "bare_name_files": [],
             "combined_delta": 0, "combined_files": [],
             "surface_count": 27, "surface": []}
        m.update(base)
        return aca.verdict(m)

    def test_zero_prose_only_files_means_membership_is_not_falsifiable(self):
        v = self._v()
        self.assertFalse(v["membership_falsifiable_here"])
        self.assertTrue(v["plant_is_the_only_coverage"])

    def test_a_prose_only_file_makes_membership_falsifiable(self):
        v = self._v(prose_only=["prose.dart"], prose_only_count=1)
        self.assertTrue(v["membership_falsifiable_here"])
        self.assertFalse(v["plant_is_the_only_coverage"])

    def test_an_absent_assertion_is_not_reported_as_the_only_coverage(self):
        # Otherwise a deleted guard reads as "the plant covers it".
        v = self._v(membership_present=False)
        self.assertFalse(v["plant_is_the_only_coverage"])
        self.assertFalse(v["membership_guarded"])


# The shape that hides a real blindness behind a clean measurement.
#
# `test/agreement_census_audit_test.py` already carries two mutation batteries
# whose first run found SURVIVORS (`prose_only_count` hardcoded, and the VACUOUS
# sentence softened -- both left the suite green because every other case drove
# `verdict()` directly and never rendered). This class is the third battery,
# built the same way, for the same reason.
#
# **What it pins.** The pin on `census.direct.length` names a mutation in its own
# comment at `test/agreement_comment_test.dart:768` -- a census that "stopped
# asking for a parenthesis AND started reading prose". That is ONE change made of
# two filters, and the tool measures the two filters SEPARATELY. On the real tree
# each one moves the count by **0** and together they move it by **+16**, so a
# tool that reports only the isolated deltas prints "PIN CANNOT SEE IT" twice and
# a reader concludes the pin is blind -- when the pin sees the actual change
# perfectly well. The tool was measuring a mutation nobody made.
class ConjunctionTests(unittest.TestCase):
    """The mutation the pin names is a conjunction, not two mutations."""

    # A file that calls in code AND quotes the helper in a comment.
    BOTH = ("// A worked example: arabicCounted(3, 'a', two: 'b') is one shape.\n"
            "String f(int n) => arabicCounted(n, 'a', two: 'b');\n")
    # The file each isolated filter CANNOT see: prose with no parenthesis.
    # `arabicCounted` named in a comment WITHOUT `(` -- so the paren filter
    # rejects it and the comment filter is the only thing hiding it.
    BARE_PROSE = ("// See [arabicCounted] for the other shape.\n"
                  "String f() => 'x';\n")

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_both_filters_off_moves_the_count_when_either_alone_does_not(self):
        # The whole finding, as one assertion: the conjunction moves the set and
        # each isolated filter does not. If either isolated delta ever becomes
        # non-zero this case goes red and the finding has to be re-measured --
        # which is the only thing a stale comment about a dead defect can do.
        root = write_tree(self.tmp, {
            "lib/a.dart": CALLER,
            "lib/b.dart": self.BARE_PROSE,
            "lib/c.dart": self.BOTH,
        })
        calls = re.compile(r"arabicCount(?:ed)?\s*\(")
        direct = aca.direct_call_sites(root, calls)
        unfiltered = aca.direct_ignoring_comments(root, calls)
        bare = re.compile(calls.pattern.replace(r"\(", ""))
        combined = aca.direct_ignoring_comments(root, bare)

        # a.dart and c.dart both CALL in code; b.dart is prose with no
        # parenthesis, which is the file neither isolated filter can see.
        self.assertEqual(sorted(direct), ["a.dart", "c.dart"])
        self.assertEqual(len(unfiltered) - len(direct), 0,
                         "the comment filter alone must move nothing here")
        self.assertEqual(len(aca.direct_call_sites(root, bare)) - len(direct), 0,
                         "the bare name alone must move nothing here")
        self.assertEqual(len(combined) - len(direct), 1,
                         "together they add b.dart, the file neither sees alone")
        self.assertEqual(sorted(set(combined) - set(direct)), ["b.dart"])

    def test_measure_publishes_the_conjunction_delta(self):
        # The field has to be in the measurement, not reconstructed by a reader.
        self.tmp2 = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp2)
        dart = ("final calls = RegExp(r'arabicCount(?:ed)?\\s*\\(');\n"
                "final _negated = RegExp(r'never\\s*$', "
                "caseSensitive: false);\n"
                "final _probeLoose = RegExp(r'(\\d+) is the plural');\n"
                "void main() { expect(census.direct.length, 1, 'w'); }\n")
        path = os.path.join(self.tmp2, aca.DART)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(dart)
        write_tree(self.tmp2, {
            "lib/a.dart": CALLER, "lib/b.dart": self.BARE_PROSE})
        m = aca.measure(self.tmp2)
        self.assertEqual(m["combined_delta"], 1)
        self.assertIn("b.dart", m["combined_files"])
        self.assertTrue(aca.verdict(m)["direct_pin_falsifiable_for_combined"])

    def test_the_verdict_flags_the_case_where_the_isolated_deltas_lie(self):
        # The three-way shape, spelled out rather than assumed: conjunction
        # non-zero, both isolated deltas zero. A tool that only reports the
        # isolated pair cannot distinguish this from "nothing to report".
        v = aca.verdict({
            "pins": {"direct": 20}, "direct": 20, "direct_files": [],
            "comment_filter_delta": 0, "comment_filter_files": [],
            "bare_name_delta": 0, "bare_name_files": [],
            "combined_delta": 16, "combined_files": ["x.dart"],
            "surface_count": 25, "surface": [],
            "membership_present": True, "membership_guarded": True,
            "prose_only": [], "prose_only_count": 0,
        })
        self.assertFalse(v["direct_pin_falsifiable_for_comment_filter"])
        self.assertFalse(v["direct_pin_falsifiable_for_bare_name"])
        self.assertTrue(v["direct_pin_falsifiable_for_combined"])
        self.assertTrue(v["isolated_deltas_hide_a_real_combined_movement"])

    def test_a_quiet_tree_is_not_flagged_as_hiding_anything(self):
        # The guard on the guard. The warning must not fire on an ordinary tree,
        # or it is a noise line that gets ignored exactly when it matters.
        v = aca.verdict({
            "pins": {"direct": 20}, "direct": 20, "direct_files": [],
            "comment_filter_delta": 0, "comment_filter_files": [],
            "bare_name_delta": 0, "bare_name_files": [],
            "combined_delta": 0, "combined_files": [],
            "surface_count": 25, "surface": [],
            "membership_present": True, "membership_guarded": True,
            "prose_only": [], "prose_only_count": 0,
        })
        self.assertFalse(v["isolated_deltas_hide_a_real_combined_movement"])
        self.assertFalse(v["direct_pin_falsifiable_for_combined"])


class ConjunctionCliTests(CliTests):
    """The render path -- where a reader is actually convinced.

    A judgement that is right in a dict and absent from the output has told
    nobody anything, which is how the previous two mutations survived.
    """

    def test_the_render_names_the_conjunction_and_its_delta(self):
        self._dart(open(os.path.join(ROOT, aca.DART), encoding="utf-8").read())
        write_tree(self.tmp, {
            "lib/caller.dart": CALLER,
            "lib/bare_prose.dart": ConjunctionTests.BARE_PROSE})
        code, out = self._capture(self.tmp)
        self.assertIn("CONJUNCTION", out)
        self.assertIn("both filters off at once", out)

    def test_the_render_says_the_isolated_lines_mislead_when_they_do(self):
        # The sentence that stops the next reader trusting the two lines above it.
        self._dart(open(os.path.join(ROOT, aca.DART), encoding="utf-8").read())
        write_tree(self.tmp, {
            "lib/caller.dart": CALLER,
            "lib/bare_prose.dart": ConjunctionTests.BARE_PROSE})
        code, out = self._capture(self.tmp)
        self.assertIn("MISLEADING ON THIS TREE", out)
        self.assertIn("files only the conjunction adds", out)
        self.assertIn("bare_prose.dart", out)

    def test_a_quiet_tree_renders_no_misleading_warning(self):
        self._dart(open(os.path.join(ROOT, aca.DART), encoding="utf-8").read())
        write_tree(self.tmp, {"lib/caller.dart": CALLER})
        code, out = self._capture(self.tmp)
        self.assertIn("CONJUNCTION", out)
        self.assertNotIn("MISLEADING ON THIS TREE", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
