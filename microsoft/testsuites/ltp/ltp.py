# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

from typing import List, Type
from lisa.executable import Tool
from lisa.operating_system import Posix, Redhat
from lisa.tools import Make, Gcc, Git
from lisa.util import SkippedException, UnsupportedDistroException


class Ltp(Tool):
    LTP_DIR_NAME = "ltp"
    LTP_TESTS_GIT_TAG = "20190930"
    LTP_GIT_URL = "https://github.com/linux-test-project/ltp.git"
    BUILD_REQUIRED_DISK_SIZE_IN_GB = 2
    TOP_BUILDDIR = "/opt/ltp"

    @property
    def command(self) -> str:
        return "./runltp"

    @property
    def dependencies(self) -> List[Type[Tool]]:
        return [Make, Gcc, Git]

    @property
    def can_install(self) -> bool:
        return True

    def run():
        pass

    def _install(self) -> bool:
        assert isinstance(self.node.os, Posix), f"{self.node.os} is not supported"

        # install common dependencies
        self.node.os.install_packages(
            [
                "m4",
                "bison",
                "flex",
                "psmisc",
                "autoconf",
                "automake",
            ]
        )

        # RedHat 8 does no longer have the ntp package
        if (
            not isinstance(self.node.os, Redhat)
            and self.node.os.information.release >= "8.0"
        ):
            self.node.os.install_packages(["ntp"])

        buildDir = self.node.find_partition_with_freespace(
            self.BUILD_REQUIRED_DISK_SIZE_IN_GB
        )

        # clone ltp
        ltp_path = self.node.tools[Git].clone(
            self.LTP_GIT_URL, cwd=buildDir, dir_name=self.LTP_DIR_NAME
        )

        # checkout tag
        self.node.tools[Git].checkout(
            ref=f"tags/{self.LTP_TESTS_GIT_TAG}", cwd=ltp_path
        )

        # build ltp with autotools
        self.node.execute("autoreconf -f 2>/dev/null", cwd=ltp_path)
        self.node.tools[Make].make("autotools 2>/dev/null", cwd=ltp_path)
        self.node.execute(
            f"./configure --prefix={self.TOP_BUILDDIR} 2>/dev/null", cwd=ltp_path
        )
