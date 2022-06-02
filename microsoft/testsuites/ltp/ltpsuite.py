# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

from typing import Any, Dict

from assertpy import assert_that

from lisa import (
    RemoteNode,
    TestCaseMetadata,
    TestSuite,
    TestSuiteMetadata,
    schema,
    search_space,
)
from lisa.node import Node
from lisa.testsuite import simple_requirement
from lisa.util.constants import RUN_LOCAL_LOG_PATH


@TestSuiteMetadata(
    area="ltp",
    category="functional",
    description="""
    This test suite is used to run Ltp related tests.
    """,
)
class Ltp(TestSuite):
    TOP_BUILDDIR = "/opt/ltp"

    LTP_RESULT_DIR = f"{RUN_LOCAL_LOG_PATH}/ltp-results.log"
    LTP_OUTPUT = f"{RUN_LOCAL_LOG_PATH}/ltp-output.log"
    LTP_LITE_TESTS = "math,fsx,ipc,mm,sched,pty,fs"
    

    @TestCaseMetadata(
        description="""
        This test case will run Ltp lite tests.
        Steps:
        1. 
        """,
        priority=3,
        requirement=simple_requirement(
            disk=schema.DiskOptionSettings(
                data_disk_count=search_space.IntRange(min=1),
                data_disk_size=search_space.IntRange(min=12),
            )
        ),
    )
    def ltp_lite(self, node: RemoteNode, variables: Dict[str, Any]) -> None:
        builddir = node.find_partition_with_freespace(
            self.BUILD_REQUIRED_DISK_SIZE_IN_GB
        )
        pass
