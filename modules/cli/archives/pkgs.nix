{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.ouch # archive extractor/creator
    pkgs.patool # universal archive unpacker (python)
    pkgs.pigz # parallel gzip backend

    pkgs._7zz # 7-Zip upstream (binary: 7zz) — replaces the unmaintained p7zip
    # pkgs.rapidgzip removed — fails on python 3.14 / setuptools 83
    # (nasmcompiler.py calls UnixCCompiler.__init__ with 4 positional args)
    pkgs.unar # archive extractor with broad format support
    pkgs.unzip # zip archive operations
    pkgs.xz # xz archiver
    pkgs.zip # zip archiver
    pkgs.wayback # self-hosted web archiving toolkit (Internet Archive / archive.today / IPFS)
  ];
}
