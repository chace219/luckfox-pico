################################################################################
#
# eipscanner
#
# Free C++ EtherNet/IP scanner (originator) — explicit + implicit (Class 1) I/O.
# Upstream: https://github.com/nimbuscontrols/EIPScanner  (MIT)
#
# We build from the Luckfox fork's C++17 port branch, because upstream master
# requires C++20 and the SDK cross toolchain is GCC 8.3 (max C++17). See
# intelligence-edge _bmad-output decision-log ADR-110.
#
# Provided via BR2_EXTERNAL (LUCKFOX_EDGE) so it survives a clean re-extract of
# the buildroot tree.
#
################################################################################

# Pinned to a COMMIT SHA (not the branch head) for reproducible builds and a
# stable download tarball. Tip of feature/cxx17-uclibc-rockchip:
#   59826b1 C++17 port · ec471f4 multicast T2O · e72fa21 bind-to-group
EIPSCANNER_VERSION = e72fa214940b4e80aa7e65d01dc65e1936f727bf
EIPSCANNER_SITE_METHOD = git
EIPSCANNER_SITE = https://github.com/chace219/EIPScanner.git
EIPSCANNER_INSTALL_STAGING = YES
EIPSCANNER_LICENSE = MIT
EIPSCANNER_LICENSE_FILES = LICENSE

# Force C++17 (GCC 8.3 has no C++20). Release build drops upstream -Werror.
EIPSCANNER_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_CXX_STANDARD=17 \
	-DCMAKE_CXX_STANDARD_REQUIRED=ON

$(eval $(cmake-package))
