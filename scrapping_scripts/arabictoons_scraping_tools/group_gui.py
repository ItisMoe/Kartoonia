#!/usr/bin/env python3
"""
Simple GUI for group_seasons.py — merges per-season show entries into one
series each and writes arabic_toons_grouped.json.

Run:  python group_gui.py
"""

import os
import json
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

import group_seasons as gs


class App:
    def __init__(self, root):
        self.root = root
        root.title("Group Seasons")
        root.geometry("680x520")
        root.minsize(560, 420)
        self._build()
        self._refresh_info()

    def _build(self):
        pad = {"padx": 10, "pady": 6}
        top = ttk.Frame(self.root); top.pack(fill="x", **pad)
        ttk.Label(top, text="Merge season/part entries into one series each",
                  font=("Segoe UI", 11, "bold")).pack(anchor="w")
        self.info = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.info).pack(anchor="w", pady=(4, 0))
        ttk.Label(top, text=f"Input:  {gs.SOURCE}\nOutput: {gs.OUTPUT}  "
                            f"(original file is left untouched)").pack(
            anchor="w", pady=(4, 0))

        btns = ttk.Frame(self.root); btns.pack(fill="x", **pad)
        self.run_btn = ttk.Button(btns, text="⤵  Group seasons now",
                                  command=self._run)
        self.run_btn.pack(side="left")
        ttk.Button(btns, text="Open output file",
                   command=self._open).pack(side="left", padx=(8, 0))
        ttk.Button(btns, text="Open folder",
                   command=lambda: os.startfile(os.getcwd())).pack(side="right")

        out = ttk.LabelFrame(self.root, text="Result")
        out.pack(fill="both", expand=True, **pad)
        self.log = scrolledtext.ScrolledText(out, height=16, wrap="word",
                                             state="disabled",
                                             font=("Consolas", 9))
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

    def _refresh_info(self):
        try:
            cat = json.load(open(gs.SOURCE, encoding="utf-8"))
            self.info.set(f"Catalog: {len(cat.get('shows', []))} show entries, "
                          f"{len(cat.get('movies', []))} movies")
        except Exception as e:
            self.info.set("Could not read catalog: " + str(e))

    def _log(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _open(self):
        if os.path.exists(gs.OUTPUT):
            os.startfile(gs.OUTPUT)
        else:
            messagebox.showinfo("Not yet", "Run the grouping first.")

    def _run(self):
        self.run_btn.configure(state="disabled")
        self.log.configure(state="normal"); self.log.delete("1.0", "end")
        self.log.configure(state="disabled")
        threading.Thread(target=self._work, daemon=True).start()

    def _work(self):
        try:
            stats = gs.run(log=lambda m: self.root.after(0, self._log, m))
            self.root.after(0, self._log, "\n✓ Done.")
            self.root.after(0, self._refresh_info)
        except Exception as e:
            self.root.after(0, messagebox.showerror, "Error", str(e))
        finally:
            self.root.after(0, lambda: self.run_btn.configure(state="normal"))


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    root = tk.Tk()
    try:
        ttk.Style().theme_use("vista")
    except Exception:
        pass
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
