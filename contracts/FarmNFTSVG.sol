// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

library FarmNFTSVG {

    // yin yang
    function getYinYangSVG() internal view returns(string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-40 -40 80 80">',
                '<circle r="39"/>',
                '<path fill="#fff" d="M0,38a38,38 0 0 1 0,-76a19,19 0 0 1 0,38a19,19 0 0 0 0,38"/>',
                '<circle r="5" cy="19" fill="#fff"/>',
                '<circle r="5" cy="-19"/>',
                '</svg>'
            ));
    }
}