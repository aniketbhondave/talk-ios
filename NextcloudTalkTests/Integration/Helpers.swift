//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import NextcloudTalk
import XCTest

extension XCTestCase {

    // TODO: This should probably be part of APIController
    func getRoomDict(from rawRoomDict: [Any]) -> [NCRoom] {
        var rooms: [NCRoom] = []
        for roomDict in rawRoomDict {
            if let roomDict = roomDict as? [AnyHashable: Any] {
                rooms.append(NCRoom(dictionary: roomDict))
            }
        }

        return rooms
    }

    func checkRoomExists(roomName: String, withAccoun account: TalkAccount) {
        let exp = expectation(description: "\(#function)\(#line)")

        NCAPIController.sharedInstance().getRoomsFor(account, updateStatus: false, modifiedSince: 0) { roomsDict, _, errorCode in
            XCTAssertEqual(errorCode, 0)

            let rooms = self.getRoomDict(from: roomsDict!)
            XCTAssertNotNil(rooms.first(where: { $0.displayName == roomName }))

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }
}
