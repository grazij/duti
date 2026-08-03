class Duti < Formula
  desc "Set default applications for document types and URL schemes on macOS"
  homepage "https://github.com/grazij/duti"
  url "https://github.com/grazij/duti/archive/refs/tags/v1.5.5%2Bgrazij.6.tar.gz"
  version "1.5.5+grazij.6"
  sha256 "488c5d4e9e6f201737444cdbfe1d8fb274d985cde1a49aebe1c1a1abf61a293c"
  license :public_domain

  # Version.detect reads a "+grazij.N" tarball name as "1", so `version` above
  # is pinned by hand and livecheck needs an explicit regex.
  livecheck do
    url :stable
    strategy :github_latest
    regex(/v?(\d+(?:\.\d+)+\+grazij\.\d+)/i)
  end

  # the tag tarball ships configure.ac, not configure
  depends_on "autoconf" => :build
  depends_on :macos

  def install
    system "autoreconf", "-if"
    # configure defaults to a universal build against an Xcode.app SDK path;
    # neither is wanted here — bottles are per-arch and CLT-only machines have
    # no Xcode.app.
    system "./configure", "--prefix=#{prefix}",
                          "--mandir=#{man}",
                          "--with-macosx-sdk=#{MacOS.sdk_path}",
                          "--with-macosx-arches=-arch #{Hardware::CPU.arch}"
    system "make"
    system "make", "install"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/duti -V").strip
    system bin/"duti", "-h"
  end
end
