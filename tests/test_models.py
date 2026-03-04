"""
tests/test_models.py
Full fixed test suite for utils/models.py

Fixes vs broken version:
  1+2. .is_web_port  ->  .is_web   (PortInfo property is named is_web)
    3. run_rustscan/httpx/etc expected True -> ALL run_* flags default False
       (CLI/orchestrator enables them based on profile, model is plain data)
"""
import pytest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from utils.models import (
    ScanProfile, NmapOptions, PortInfo, ScanConfig,
    VulnFinding, SEVERITY_PORTS, WEB_PORTS, VALID_TIMINGS,
)


# ── ScanProfile ───────────────────────────────────────────────────────────────

class TestScanProfile:
    def test_all_profiles_exist(self):
        values = [p.value for p in ScanProfile]
        for name in ["fast","standard","thorough","stealth",
                     "custom","full_suite","web_only","port_only"]:
            assert name in values

    def test_from_string(self):
        assert ScanProfile("fast")       == ScanProfile.FAST
        assert ScanProfile("full_suite") == ScanProfile.FULL_SUITE
        assert ScanProfile("port_only")  == ScanProfile.PORT_ONLY

    def test_invalid_raises(self):
        with pytest.raises(ValueError):
            ScanProfile("hacker_mode")


# ── NmapOptions ───────────────────────────────────────────────────────────────

class TestNmapOptions:
    def test_defaults(self):
        o = NmapOptions()
        assert o.all_ports         is False
        assert o.top_ports         == 1000
        assert o.scripts           is True
        assert o.version_detection is True
        assert o.os_detection      is False
        assert o.aggressive        is False
        assert o.stealth           is False
        assert o.timing            == "T4"
        assert o.extra_flags       == []
        assert o.script_args       is None

    def test_invalid_timing_raises(self):
        with pytest.raises(ValueError):
            NmapOptions(timing="T9")
        with pytest.raises(ValueError):
            NmapOptions(timing="superfast")

    def test_all_valid_timings(self):
        for t in VALID_TIMINGS:
            assert NmapOptions(timing=t).timing == t

    def test_negative_ports_raises(self):
        with pytest.raises(ValueError):
            NmapOptions(top_ports=-1)

    def test_normal_uses_sT(self):
        assert "-sT" in NmapOptions().as_nmap_args()

    def test_stealth_uses_sS_not_sT(self):
        args = NmapOptions(stealth=True, timing="T2").as_nmap_args()
        assert "-sS" in args and "-sT" not in args

    def test_aggressive_uses_A_not_sT(self):
        args = NmapOptions(aggressive=True).as_nmap_args()
        assert "-A" in args and "-sT" not in args

    def test_never_both_sT_and_sS(self):
        for o in [NmapOptions(),
                  NmapOptions(stealth=True, timing="T2"),
                  NmapOptions(aggressive=True)]:
            a = o.as_nmap_args()
            assert not ("-sT" in a and "-sS" in a)

    def test_scripts_on_off(self):
        assert "-sC" in     NmapOptions(scripts=True).as_nmap_args()
        assert "-sC" not in NmapOptions(scripts=False).as_nmap_args()

    def test_version_on_off(self):
        assert "-sV" in     NmapOptions(version_detection=True).as_nmap_args()
        assert "-sV" not in NmapOptions(version_detection=False).as_nmap_args()

    def test_os_detection_flag(self):
        assert "-O" in NmapOptions(os_detection=True, aggressive=False).as_nmap_args()

    def test_all_ports_flag(self):
        args = NmapOptions(all_ports=True).as_nmap_args()
        assert "-p-" in args and "--top-ports" not in args

    def test_top_ports_flag(self):
        args = NmapOptions(top_ports=500).as_nmap_args()
        assert "--top-ports" in args and "500" in args

    def test_timing_flag(self):
        for t in ["T1","T2","T3","T4","T5"]:
            assert f"-{t}" in NmapOptions(timing=t).as_nmap_args()

    def test_extra_flags_passed(self):
        args = NmapOptions(extra_flags=["--open","-v"]).as_nmap_args()
        assert "--open" in args and "-v" in args

    def test_script_args_included(self):
        args = NmapOptions(script_args="vulners.mincvss=5").as_nmap_args()
        assert any("script-args" in f for f in args)

    def test_fast_profile_shape(self):
        args = NmapOptions(top_ports=100, scripts=False, version_detection=False).as_nmap_args()
        assert "-sT"         in args
        assert "-sC"         not in args
        assert "-sV"         not in args
        assert "--top-ports" in args
        assert "100"         in args


# ── PortInfo ──────────────────────────────────────────────────────────────────

class TestPortInfo:
    def test_construction(self):
        p = PortInfo(port=80, protocol="tcp", state="open", service="http")
        assert p.port == 80 and p.state == "open"

    def test_severity_critical(self):
        for port in [21, 22, 23, 25, 139, 445]:
            sev = PortInfo(port=port, protocol="tcp", state="open").severity
            assert sev == "critical", f"Port {port} got {sev!r}"

    def test_severity_high(self):
        for port in [80, 443, 3306, 3389]:
            sev = PortInfo(port=port, protocol="tcp", state="open").severity
            assert sev == "high", f"Port {port} got {sev!r}"

    def test_severity_unknown_is_info(self):
        assert PortInfo(port=54321, protocol="tcp", state="open").severity == "info"

    # FIX 1+2: was .is_web_port -- correct name is .is_web
    def test_is_web_true(self):
        for port in WEB_PORTS:
            assert PortInfo(port=port, protocol="tcp", state="open").is_web is True

    def test_is_web_false(self):
        assert PortInfo(port=22,  protocol="tcp", state="open").is_web is False
        assert PortInfo(port=445, protocol="tcp", state="open").is_web is False

    def test_display_state_open(self):
        assert "open" in PortInfo(port=80, protocol="tcp", state="open").display_state

    def test_empty_defaults(self):
        p = PortInfo(port=443, protocol="tcp", state="open")
        assert p.product    == ""
        assert p.version    == ""
        assert p.extra_info == ""
        assert p.scripts    == {}


# ── ScanConfig ────────────────────────────────────────────────────────────────

class TestScanConfig:
    def test_target_stored(self):
        assert ScanConfig(target="192.168.1.1").target == "192.168.1.1"

    def test_default_profile(self):
        assert ScanConfig(target="x").profile == ScanProfile.STANDARD

    # FIX 3: ALL run_* flags default to False in models.py
    # The CLI/orchestrator enables them based on the chosen scan profile.
    def test_all_feature_flags_default_false(self):
        cfg = ScanConfig(target="x")
        for attr in ("run_subdomains","run_rustscan","run_feroxbuster",
                     "run_masscan","run_aquatone","run_whatweb",
                     "run_nikto","run_nuclei","run_httpx","run_ai_analysis"):
            assert getattr(cfg, attr) is False, f"{attr} should default to False"

    def test_async_defaults(self):
        cfg = ScanConfig(target="x")
        assert cfg.async_concurrency == 1000
        assert cfg.async_timeout     == 1.5

    def test_nmap_opts_type(self):
        assert isinstance(ScanConfig(target="x").nmap_opts, NmapOptions)

    def test_to_dict_contains_target(self):
        assert ScanConfig(target="10.0.0.1").to_dict()["target"] == "10.0.0.1"

    def test_to_dict_profile_is_string(self):
        # to_dict() must convert the Enum to its .value string
        assert ScanConfig(target="x").to_dict()["profile"] == "standard"

    def test_thread_default(self):
        assert ScanConfig(target="x").threads == 20

    def test_masscan_rate_default(self):
        assert ScanConfig(target="x").masscan_rate == 5000

    def test_output_dir_default(self):
        assert ScanConfig(target="x").output_dir == "reports"

    def test_wordlist_size_default(self):
        assert ScanConfig(target="x").wordlist_size == "medium"


# ── VulnFinding ───────────────────────────────────────────────────────────────

class TestVulnFinding:
    def test_construction(self):
        v = VulnFinding(tool="nuclei", severity="high", title="RCE",
                        target="http://x.com", cve="CVE-2024-1")
        assert v.tool == "nuclei" and v.cve == "CVE-2024-1"

    def test_all_severities(self):
        for sev in ("critical","high","medium","low","info"):
            assert VulnFinding(tool="t", severity=sev, title="x", target="x").severity == sev

    def test_cve_default_empty(self):
        assert VulnFinding(tool="t", severity="low", title="x", target="x").cve == ""

    def test_details_default_empty(self):
        assert VulnFinding(tool="t", severity="low", title="x", target="x").details == ""


# ── Constants ─────────────────────────────────────────────────────────────────

class TestConstants:
    def test_severity_ports_keys(self):
        for k in ("critical","high","medium"):
            assert k in SEVERITY_PORTS

    def test_critical_ssh_smb_telnet(self):
        assert 22  in SEVERITY_PORTS["critical"]
        assert 445 in SEVERITY_PORTS["critical"]
        assert 23  in SEVERITY_PORTS["critical"]

    def test_high_http_https_mysql(self):
        assert 80   in SEVERITY_PORTS["high"]
        assert 443  in SEVERITY_PORTS["high"]
        assert 3306 in SEVERITY_PORTS["high"]

    def test_web_ports_has_common(self):
        for p in [80, 443, 8080, 8443]:
            assert p in WEB_PORTS

    def test_valid_timings_exact(self):
        assert VALID_TIMINGS == {"T1","T2","T3","T4","T5"}

    def test_web_ports_is_set(self):
        assert isinstance(WEB_PORTS, (set, frozenset))

    def test_severity_ports_values_are_sets(self):
        for k, v in SEVERITY_PORTS.items():
            assert isinstance(v, (set, frozenset)), f"{k} should be a set"
