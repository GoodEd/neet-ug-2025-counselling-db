from etl.neetcounselling2025 import run_admitted_joined_tabula as mod
import sys


def test_build_page_windows_exact_multiple():
    windows = mod.build_page_windows(total_pages=20, chunk_size=10)
    assert windows == [(1, 10), (11, 20)]


def test_build_page_windows_with_tail_chunk():
    windows = mod.build_page_windows(total_pages=23, chunk_size=10)
    assert windows == [(1, 10), (11, 20), (21, 23)]


def test_build_page_windows_small_total():
    windows = mod.build_page_windows(total_pages=7, chunk_size=10)
    assert windows == [(1, 7)]


def test_filter_completed_windows_skips_finished_ranges():
    windows = [(1, 10), (11, 20), (21, 30)]
    completed = {(1, 10), (21, 30)}

    pending = mod.filter_completed_windows(windows, completed)

    assert pending == [(11, 20)]


def test_filter_completed_windows_keeps_all_when_nothing_completed():
    windows = [(1, 10), (11, 20)]

    pending = mod.filter_completed_windows(windows, set())

    assert pending == windows


def test_ensure_repo_root_on_sys_path_prepends_missing_root(tmp_path, monkeypatch):
    monkeypatch.setattr(sys, "path", [p for p in sys.path if p != str(tmp_path)])

    mod.ensure_repo_root_on_sys_path(tmp_path)

    assert sys.path[0] == str(tmp_path)
