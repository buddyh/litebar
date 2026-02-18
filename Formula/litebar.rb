class Litebar < Formula
  desc "Menu bar observability for SQLite-backed systems"
  homepage "https://github.com/buddyh/litebar"
  license "MIT"
  head "https://github.com/buddyh/litebar.git", branch: "main"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release"
    bin.install ".build/release/Litebar" => "litebar"
  end

  test do
    assert_predicate bin/"litebar", :exist?
  end
end
