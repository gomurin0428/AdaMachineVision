from pathlib import Path
import sys
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_DIR))

from tools.check_axioms import EXPECTED_PROOFS, validate_audit_output


def audit_output(names: tuple[str, ...], dependent: frozenset[str] = frozenset()) -> str:
    lines = []
    for name in names:
        proof = f"CameraLifecycle.{name}"
        if name in dependent:
            lines.append(f"'{proof}' depends on axioms: [propext]")
        else:
            lines.append(f"'{proof}' does not depend on any axioms")
    return "\n".join(lines)


class AxiomAuditTests(unittest.TestCase):
    def test_exact_expected_theorems_pass(self) -> None:
        valid, _ = validate_audit_output(audit_output(EXPECTED_PROOFS))
        self.assertTrue(valid)

    def test_duplicate_and_missing_name_with_same_count_fails(self) -> None:
        names = list(EXPECTED_PROOFS)
        names[-1] = names[0]
        valid, message = validate_audit_output(audit_output(tuple(names)))
        self.assertFalse(valid)
        self.assertIn("names do not match", message)

    def test_unexpected_name_fails(self) -> None:
        names = list(EXPECTED_PROOFS)
        names[-1] = "unexpected_theorem"
        valid, message = validate_audit_output(audit_output(tuple(names)))
        self.assertFalse(valid)
        self.assertIn("names do not match", message)

    def test_axiom_dependency_fails(self) -> None:
        valid, message = validate_audit_output(
            audit_output(EXPECTED_PROOFS, frozenset({EXPECTED_PROOFS[0]}))
        )
        self.assertFalse(valid)
        self.assertEqual(message, "proof theorem depends on axioms")


if __name__ == "__main__":
    unittest.main()
