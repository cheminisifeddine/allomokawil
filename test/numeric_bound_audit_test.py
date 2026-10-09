#!/usr/bin/env python3
"""Pin the judgements `tool/numeric_bound_audit.py` reasons with -- python, not Dart.

    python3 test/numeric_bound_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refuses Dart on
this host (608 MB available against a 900 MB floor; the difference is a
hypervisor balloon nothing in this PID namespace owns). The fix this tool
measures is **Dart**, so it cannot be applied here -- but a tick needs the
measurement before it edits, and a measurement does not need a Dart VM. Same
reasoning `test/agreement_census_audit_test.py` records for itself.

**No case reads the REAL tree.** Every case plants a tree in a temp directory
and drives the tool's own functions against it. A case asserting "the tree holds
six unroofed fields" is the same stale number wearing a test's clothes: it would
go red the next time a field gains a bound, and would tell nobody why.

**What this battery must protect.** Three ways the judgement can lie, each of
which this file has already been caught by at least once:

  * a lookup miss becoming a PASS -- a field whose parser was never found must
    be reported ABSENT, never scored as bounded (the census tool shipped a
    `guarded: True` beside a `present: False` once already);
  * a lookup miss becoming a DEFECT -- a pattern too strict to match a bound
    that IS there invents a finding. `profile_years` hit this exactly: a
    trailing comma made the regex miss the one field in the app that has a
    real roof;
  * a fixture that does not compile against the reader it tests -- a body
    naming `newValue` under a signature that says `b` tests nothing, and does
    it silently.

**And the fixtures are built to be coherent by construction**: every planted
screen is assembled from one `parse()` helper, so a case cannot accidentally
ship a tree whose two halves disagree.
"""

from __future__ import annotations

import importlib.util
import json as jsonlib
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(ROOT, "tool", "numeric_bound_audit.py")

DZ_REL = os.path.join("lib", "src", "core", "text", "dz_number.dart")
NF_REL = os.path.join("lib", "src", "widgets", "number_field.dart")
DET_REL = os.path.join("lib", "src", "screens", "project",
                       "project_detail_screen.dart")
NEW_REL = os.path.join("lib", "src", "screens", "project",
                       "project_new_screen.dart")
PRO_REL = os.path.join("lib", "src", "screens", "worker",
                       "profile_edit_screen.dart")

ROOF_AMOUNT = 900000000000
ROOF_DAYS = 3650


def load_tool():
    spec = importlib.util.spec_from_file_location("nba", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nba = load_tool()


def dz_src(cap=12, years=70):
    return """
class DzNumber {
  static const int maxDigits = %d;
  static const int maxExperienceYears = %d;
}
""" % (cap, years)


def fmt_src(truncates=True, refuses_fraction=True):
    """The formatter, faithful to `dz_number.dart`'s real signature."""
    frac = ("if (DzNumber.hasFraction(newValue.text)) return oldValue;"
            if refuses_fraction else "")
    over = ("if (digits.length > maxDigits) digits = "
            "digits.substring(0, maxDigits);" if truncates
            else "if (digits.length > maxDigits) return oldValue;")
    return """
class DzNumberInputFormatter extends TextInputFormatter {
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    %s
    var digits = DzNumber.digits(newValue.text);
    %s
    return TextEditingValue(text: digits);
  }
}
""" % (frac, over)


def number_field_src(follows=True, overrides=()):
    cap = "DzNumber.maxDigits" if follows else "8"
    blocks = "\n".join(
        "  NumberField(controller: %s, maxDigits: %d)," % (c, d)
        for c, d in overrides)
    return """
class NumberField extends StatelessWidget {
  const NumberField({this.maxDigits = %s});
  final int maxDigits;
  Widget build(BuildContext context) {
    return TextField(
      inputFormatters: [DzNumberInputFormatter(maxDigits: maxDigits)],
    );
  }
}
%s
""" % (cap, blocks)


def detail_src(amount_roof=None, days_roof=None):
    """The bid sheet. `capped` and `uncapped` variants of the SAME call."""
    amt = ", min: 1000" + (", max: %d" % amount_roof if amount_roof else "")
    day = ", min: 1" + (", max: %d" % days_roof if days_roof else "")
    return """
class DetailScreen {
  void go() {
    final amt = DzNumber.tryParse(rawAmount%s);
    final rawDays = _days.text.trim();
    if (rawDays.isNotEmpty && DzNumber.tryParse(rawDays%s) == null) {}
    final amount = DzNumber.tryParse(submitted.amount, min: 1000);
  }
}
""" % (amt, day)


def new_src(min_roof=None, max_roof=None):
    a = (", max: %d" % min_roof) if min_roof else ""
    b = (", max: %d" % max_roof) if max_roof else ""
    return """
class NewScreen {
  int? get _budgetMinValue => DzNumber.tryParse(_budgetMin.text%s);
  int? get _budgetMaxValue => DzNumber.tryParse(_budgetMax.text%s);
}
""" % (a, b)


def profile_src(min_roof=None, max_roof=None, years_trailing_comma=True):
    a = (", max: %d" % min_roof) if min_roof else ""
    b = (", max: %d" % max_roof) if max_roof else ""
    tail = ",\n    " if years_trailing_comma else "\n    "
    return """
class ProfileEditScreen {
  Future<void> _save() async {
    final min = DzNumber.tryParse(_minPrice.text%s);
    final max = DzNumber.tryParse(_maxPrice.text%s);
    final years = DzNumber.tryParse(_years.text,
      max: DzNumber.maxExperienceYears%s);
  }
}
""" % (a, b, tail)


def plant(root, dz=None, fmt=None, detail=None, new=None, profile=None, nf=None):
    """Write a whole tree. Every screen is assembled from its own helper, so a
    case cannot plant a tree whose halves disagree."""
    files = {
        DZ_REL: (dz if dz is not None else dz_src()) +
               (fmt if fmt is not None else fmt_src()),
        NF_REL: nf if nf is not None else number_field_src(),
        DET_REL: detail if detail is not None else detail_src(),
        NEW_REL: new if new is not None else new_src(),
        PRO_REL: profile if profile is not None else profile_src(),
    }
    for rel, body in files.items():
        full = os.path.join(root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(body)
    return root


class PlantCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="nba-")
        self.addCleanup(self._rm, self.dir)

    @staticmethod
    def _rm(path):
        import shutil
        shutil.rmtree(path, ignore_errors=True)

    def measure(self, **kw):
        return nba.measure(plant(self.dir, **kw))

    def verdict(self, **kw):
        return nba.verdict(self.measure(**kw))

    def run_tool(self, expect=None, **kw):
        tree = plant(self.dir, **kw)
        proc = subprocess.run([sys.executable, TOOL, "--root", tree],
                              capture_output=True, text=True)
        if expect is not None:
            self.assertEqual(proc.returncode, expect, proc.stdout + proc.stderr)
        return proc


class TestCapsAreReadNotCarried(PlantCase):
    def test_parser_cap_comes_from_the_tree(self):
        self.assertEqual(self.measure(dz=dz_src(cap=9))["parser_cap"], 9)

    def test_years_cap_comes_from_the_tree(self):
        m = self.measure(dz=dz_src(years=40))
        self.assertEqual(m["years_cap"], 40)
        y = field(m, "profile_years")
        self.assertEqual(y["parse_max"], 40)

    def test_a_renamed_constant_exits_2_rather_than_guessing(self):
        tree = plant(self.dir, dz="class DzNumber { /* renamed */ }")
        proc = subprocess.run([sys.executable, TOOL, "--root", tree],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("UNREADABLE", proc.stdout)

    def test_missing_file_exits_2_not_a_traceback(self):
        tree = plant(self.dir)
        os.remove(os.path.join(tree, DZ_REL))
        proc = subprocess.run([sys.executable, TOOL, "--root", tree],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("UNREADABLE", proc.stdout)


class TestTheRoofSplit(PlantCase):
    def test_a_min_without_a_max_is_unroofed(self):
        v = self.verdict()
        self.assertIn("bid_days", v["unroofed"])
        self.assertIn("bid_amount", v["unroofed"])

    def test_the_one_field_with_a_real_roof_is_reported_roofed(self):
        y = field(self.measure(), "profile_years")
        self.assertTrue(y["parse_found"])
        self.assertTrue(y["roofed"])
        self.assertEqual(y["parse_max"], 70)
        self.assertNotIn("profile_years", self.verdict()["unroofed"])

    def test_adding_a_max_roofs_a_budget_field(self):
        v = self.verdict(new=new_src(min_roof=ROOF_AMOUNT))
        self.assertNotIn("budget_min", v["unroofed"])

    def test_a_trailing_comma_does_not_hide_a_bound(self):
        """Regression: a strict pattern invented a defect on the one bounded
        field in the app. A miss must never read as `unroofed`."""
        for comma in (True, False):
            y = field(self.measure(
                profile=profile_src(years_trailing_comma=comma)),
                "profile_years")
            self.assertTrue(y["parse_found"], "years missed (comma=%s)" % comma)
            self.assertEqual(y["parse_max"], 70)

    def test_a_parser_that_is_absent_is_reported_not_scored(self):
        m = self.measure(detail="class DetailScreen { void go() {} }")
        v = nba.verdict(m)
        self.assertIn("bid_days", v["parser_missing"])
        self.assertNotIn("bid_days", v["unroofed"])

    def test_a_missing_parser_keeps_the_run_red_on_its_own(self):
        """Absent is not clean, and it must be able to say so ALONE.

        The earlier version of this case was masked: it dropped the detail
        screen's parsers while every other field was still unroofed, so
        `drift` stayed true from the roofs and the case passed with `missing`
        deleted from the verdict entirely. It now plants an otherwise-CLEAN
        tree, so `parser_missing` is the only thing that can make it red --
        which is what makes the mutant killable.
        """
        proc = self.run_tool(
            expect=1,
            fmt=fmt_src(truncates=False),
            detail="class DetailScreen { void go() {} }",
            new=new_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT),
            profile=profile_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT))
        self.assertIn("Parser not found", proc.stdout)

    def test_render_lists_the_missing_parsers_it_found(self):
        m = self.measure(detail="class DetailScreen { void go() {} }")
        out = "\n".join(nba.render(m, nba.verdict(m)))
        self.assertIn("bid_days", out)
        self.assertIn("bid_amount", out)


class TestFormatterBehaviour(PlantCase):
    def test_the_tree_as_it_reads_truncates_and_refuses(self):
        m = self.measure()
        self.assertTrue(m["over_long_truncates"])
        self.assertTrue(m["fraction_refused"])

    def test_refusing_an_over_long_paste_is_that_half_of_the_fix(self):
        """The two halves are INDEPENDENT. Refusing the truncation must be seen,
        and must NOT be reported as clearing the whole finding -- the roofs are
        a separate defect with a separate fix, and an audit that let one tick's
        work switch the light green for both is exactly the failure mode the
        `drift` key exists to prevent."""
        m = self.measure(fmt=fmt_src(truncates=False))
        self.assertFalse(m["over_long_truncates"])
        self.assertTrue(nba.verdict(m)["drift"])
        self.assertIn("bid_days", nba.verdict(m)["unroofed"])

    def test_truncating_a_fraction_is_the_other_half(self):
        self.assertFalse(self.measure(
            fmt=fmt_src(refuses_fraction=False))["fraction_refused"])

    def test_renamed_parameters_are_still_read(self):
        renamed = fmt_src().replace("oldValue", "before").replace("newValue", "after")
        self.assertTrue(nba.fraction_is_refused(renamed))
        self.assertTrue(nba.truncation_is_silent(renamed))

    def test_a_missing_signature_exits_2_rather_than_guessing(self):
        tree = plant(self.dir, fmt="\nclass F { void other() {} }\n")
        proc = subprocess.run([sys.executable, TOOL, "--root", tree],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)

    def test_the_box_default_following_the_parser_is_reported(self):
        self.assertTrue(self.measure()["box_default_follows_parser"])

    def test_a_default_that_leaves_the_parser_is_reported(self):
        m = self.measure(nf=number_field_src(follows=False))
        self.assertFalse(m["box_default_follows_parser"])

    def test_a_per_field_override_is_seen(self):
        m = self.measure(
            nf=number_field_src(overrides=[("_days", 4)]),
            detail=detail_src())
        self.assertIn(["_days", 4], m["box_overrides"])


class TestVerdictIsHonest(PlantCase):
    def test_a_fully_fixed_tree_is_clean(self):
        """Every field roofed AND the formatter refusing rather than truncating."""
        v = self.verdict(
            fmt=fmt_src(truncates=False),
            detail=detail_src(amount_roof=ROOF_AMOUNT, days_roof=ROOF_DAYS),
            new=new_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT),
            profile=profile_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT))
        self.assertEqual(v["unroofed"], [], "unroofed: %s" % v["unroofed"])
        self.assertEqual(v["parser_missing"], [])
        self.assertFalse(v["drift"])

    def test_the_real_tree_is_red(self):
        self.assertTrue(self.verdict()["drift"])


class TestRenderShowsTheFinding(PlantCase):
    def test_render_names_the_unroofed_fields(self):
        m = self.measure()
        out = "\n".join(nba.render(m, nba.verdict(m)))
        self.assertIn("NO ROOF", out)

    def test_render_lists_each_unroofed_field_by_name(self):
        """The section header alone is not the finding -- a render that said
        "6 of 7 fields" and then named none would satisfy the case above."""
        m = self.measure()
        out = "\n".join(nba.render(m, nba.verdict(m)))
        for fid in nba.verdict(m)["unroofed"]:
            self.assertRegex(out, r"(?m)^\s+%s\b" % re.escape(fid),
                             "render never named %s" % fid)

    def test_render_gives_each_unroofed_field_its_arabic_label(self):
        """The table names every field, so a per-field list that only repeated
        the id would be decoration. Its job is to say WHICH BOX on screen to
        go and fix -- `bid_days` alone does not mean anything to the man who
        has to find it, «مدة الإنجاز (أيام)» does."""
        m = self.measure()
        out = "\n".join(nba.render(m, nba.verdict(m)))
        for f in m["fields"]:
            if f["id"] in nba.verdict(m)["unroofed"]:
                self.assertIn(f["field"], out,
                              "render never named the field «%s»" % f["field"])

    def test_render_does_not_list_a_roofed_field_as_unroofed(self):
        m = self.measure()
        out = "\n".join(nba.render(m, nba.verdict(m)))
        block = out.split("DEFECT")[-1]
        self.assertNotIn("profile_years", block)

    def test_render_reports_the_silent_truncation(self):
        """The truncation is the louder finding; a summary that printed six
        unroofed fields while hiding it would be burying it."""
        out = "\n".join(nba.render(self.measure(),
                                   nba.verdict(self.measure())))
        self.assertIn("TRUNCATED silently", out)

    def test_render_prints_the_one_roofed_field_as_roofed(self):
        out = "\n".join(nba.render(self.measure(),
                                   nba.verdict(self.measure())))
        self.assertRegex(out, r"profile_years\s+12\s+-\s+70")

    def test_render_never_says_clean_while_a_parser_is_missing(self):
        m = self.measure(detail="class DetailScreen { void go() {} }")
        out = "\n".join(nba.render(m, nba.verdict(m)))
        self.assertIn("Parser not found", out)


class TestCLI(PlantCase):
    def test_exit_1_on_the_shape_as_it_reads(self):
        self.run_tool(expect=1)

    def test_exit_0_when_the_fixer_has_run(self):
        self.run_tool(
            expect=0,
            fmt=fmt_src(truncates=False),
            detail=detail_src(amount_roof=ROOF_AMOUNT, days_roof=ROOF_DAYS),
            new=new_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT),
            profile=profile_src(min_roof=ROOF_AMOUNT, max_roof=ROOF_AMOUNT))

    def test_json_carries_the_verdict_and_the_behaviour(self):
        tree = plant(self.dir)
        proc = subprocess.run([sys.executable, TOOL, "--root", tree, "--json"],
                              capture_output=True, text=True)
        payload = jsonlib.loads(proc.stdout)
        self.assertEqual(payload["parser_cap"], 12)
        self.assertIn("bid_days", payload["unroofed"])
        self.assertTrue(payload["over_long_truncates"])
        self.assertTrue(payload["fraction_refused"])


def field(m, fid):
    for f in m["fields"]:
        if f["id"] == fid:
            return f
    raise AssertionError("no field %r in %s" % (fid, [f["id"] for f in m["fields"]]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
