# PeaZip APT mirror

Unofficial Debian packages of [PeaZip](https://peazip.github.io/), repacked from upstream Qt6 and GTK2 `.deb`s as:

- `peazip-qt6`
- `peazip-gtk2`

Install from the combined APT repo:

```sh
curl -fsSL https://jochemkuipers.github.io/apt-repo/jochem.sources \
  | sudo tee /etc/apt/sources.list.d/jochem.sources
sudo apt update
sudo apt install peazip-qt6   # or: peazip-gtk2
```

Only one widgetset can be installed at a time (they conflict).

This repo watches [peazip/PeaZip releases](https://github.com/peazip/PeaZip/releases), verifies SHA256, rewrites the package name, and publishes GitHub Releases consumed by [apt-repo](https://github.com/JochemKuipers/apt-repo).
