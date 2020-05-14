const std = @import("std");
const testing = std.testing;

pub const IloLicenseKey = struct {
    product_id_1: u10,
    product_ver_1: u4,
    product_id_2: u10,
    product_ver_2: u4,
    product_id_3: u10,
    product_ver_3: u4,
    license_type: u4,
    transaction_date: u14,
    transaction_number: u18,
    seats_demo: u16,
    feature_mask: u4,
    reserved: u1,

    const alphabet = "23456789BCDGHJKLMNPQRSTVWXYZ";
    const magic1: u128 = 0x65424a64633535322c6d50616a23; // #jaPm,255cdJBe
    const magic2 = [_]u32{
        10, 4,  10, 4,
        10, 4,  4,  14,
        18, 16, 4,  1,
        16,
    };

    pub const Error = error{
        WrongKeyLength,
        WrongFirstCharacter,
        CharacterNotInAlphabet,
        ChecksumError,
    };

    pub fn from_string(key: []const u8) !IloLicenseKey {
        if (key.len != 25) {
            return Error.WrongKeyLength;
        }

        if (key[0] != alphabet[1]) {
            return Error.WrongFirstCharacter;
        }

        const key_as_int = blk: {
            var result: u128 = 0;
            for (key[1..]) |c| {
                result *= alphabet.len;
                if (memchr(alphabet, c)) |pos| {
                    result += pos;
                } else {
                    return Error.CharacterNotInAlphabet;
                }
            }
            break :blk result;
        };

        const key_xored = key_as_int ^ magic1;

        const unscrambled_key = blk: {
            var result = [_]u32{0} ** 13;
            var foo = [_]u32{0} ** 13;
            var w: u128 = 1;
            var i: u8 = 0;
            while (i < 32) : (i += 1) {
                var j: u8 = 0;
                while (j < 13) : (j += 1) {
                    if (foo[j] < magic2[j]) {
                        if (key_xored & w != 0) {
                            result[j] |= @as(u32, 1) << @intCast(u5, foo[j]);
                        }
                        w <<= 1;
                        foo[j] += 1;
                    }
                }
            }
            break :blk result;
        };

        if (unscrambled_key[12] != checksum(unscrambled_key[0..12])) {
            return Error.ChecksumError;
        }

        return IloLicenseKey{
            .product_id_1 = @intCast(u10, unscrambled_key[0]),
            .product_ver_1 = @intCast(u4, unscrambled_key[1]),
            .product_id_2 = @intCast(u10, unscrambled_key[2]),
            .product_ver_2 = @intCast(u4, unscrambled_key[3]),
            .product_id_3 = @intCast(u10, unscrambled_key[4]),
            .product_ver_3 = @intCast(u4, unscrambled_key[5]),
            .license_type = @intCast(u4, unscrambled_key[6]),
            .transaction_date = @intCast(u14, unscrambled_key[7]),
            .transaction_number = @intCast(u18, unscrambled_key[8]),
            .seats_demo = @intCast(u16, unscrambled_key[9]),
            .feature_mask = @intCast(u4, unscrambled_key[10]),
            .reserved = @intCast(u1, unscrambled_key[11]),
        };
    }

    pub fn to_string(self: IloLicenseKey) [25]u8 {
        var data: [13]u32 = .{
            self.product_id_1,
            self.product_ver_1,
            self.product_id_2,
            self.product_ver_2,
            self.product_id_3,
            self.product_ver_3,
            self.license_type,
            self.transaction_date,
            self.transaction_number,
            self.seats_demo,
            self.feature_mask,
            self.reserved,
            0,
        };
        data[12] = checksum(data[0..12]);

        const scrambled_key: u128 = blk: {
            var result: u128 = 0;
            var foo = [_]u32{0} ** 13;
            var w: u128 = 1;
            var i: u8 = 0;
            while (i < 32) : (i += 1) {
                var j: u8 = 0;
                while (j < 13) : (j += 1) {
                    if (foo[j] < magic2[j]) {
                        if (data[j] & @as(u32, 1) << @intCast(u5, foo[j]) != 0) {
                            result |= w;
                        }
                        w <<= 1;
                        foo[j] += 1;
                    }
                }
            }
            break :blk result;
        };

        var key_as_int = scrambled_key ^ magic1;

        return blk: {
            var result = [_]u8{'3'} ++ [_]u8{0} ** 24;
            var i: u8 = 24;
            while (i > 0) : (i -= 1) {
                result[i] = alphabet[@intCast(usize, @mod(key_as_int, alphabet.len))];
                key_as_int /= alphabet.len;
            }
            break :blk result;
        };
    }

    fn memchr(s: []const u8, c: u8) ?usize {
        var i: usize = 0;
        for (s) |b| {
            if (b == c) {
                return i;
            }
            i += 1;
        }
        return null;
    }

    fn checksum(data: []const u32) u32 {
        var x: u32 = 0x4242;
        for (data) |d| {
            const y: u32 = x >> 14;
            x <<= 2;
            if ((x & 0x20000) != 0) {
                x |= y;
                x |= 2;
            } else {
                x |= y & 1;
            }
            x <<= 16;
            x ^= d;
            x ^= d << 16;
            x >>= 16;
        }
        return x;
    }

    pub fn format_transaction_date(self: IloLicenseKey) [10]u8 {
        const year = self.transaction_date / 384 + 2001;
        const month = @mod(self.transaction_date, 384) / 32;
        const day = @mod(self.transaction_date, 32);
        var result: [10]u8 = undefined;
        _ = std.fmt.bufPrint(result[0..], "{:0>4}-{:0>2}-{:0>2}", .{ year, month, day }) catch unreachable;
        return result;
    }
};

test "IloLicenseKey.from_string (valid)" {
    const license = try IloLicenseKey.from_string("3Q23VVTZ39HLB6LYNMNCC8YRN");
    testing.expect(license.product_id_1 == 6); // Reserved for Test (#1)
    testing.expect(license.product_ver_1 == 1);
    testing.expect(license.product_id_2 == 0);
    testing.expect(license.product_ver_2 == 0);
    testing.expect(license.product_id_3 == 0);
    testing.expect(license.product_ver_3 == 0);
    testing.expect(license.license_type == 1); // FQL
    testing.expect(license.transaction_date == 7470); // 2020-05-14
    testing.expect(license.transaction_number == 0x3ffff);
    testing.expect(license.seats_demo == 1337);
    testing.expect(license.feature_mask == 0);
    testing.expect(license.reserved == 0);
}

test "IloLicenseKey.from_string (wrong key length)" {
    testing.expectError(IloLicenseKey.Error.WrongKeyLength, IloLicenseKey.from_string("3Q23VVTZ39HLB"));
}

test "IloLicenseKey.from_string (wrong first character)" {
    testing.expectError(IloLicenseKey.Error.WrongFirstCharacter, IloLicenseKey.from_string("4Q23VVTZ39HLB6LYNMNCC8YRN"));
}

test "IloLicenseKey.from_string (character not in alphabet)" {
    testing.expectError(IloLicenseKey.Error.CharacterNotInAlphabet, IloLicenseKey.from_string("3AAAAAAAA9HLB6LYNMNCC8YRN"));
}

test "IloLicenseKey.from_string (checksum error)" {
    testing.expectError(IloLicenseKey.Error.ChecksumError, IloLicenseKey.from_string("3Q23VVTZ39HLB6LYNMNCC8YRX"));
}

test "IloLicenseKey.to_string" {
    const license = IloLicenseKey{
        .product_id_1 = 6, // Reserved for Test (#1)
        .product_ver_1 = 1,
        .product_id_2 = 0,
        .product_ver_2 = 0,
        .product_id_3 = 0,
        .product_ver_3 = 0,
        .license_type = 1, // FQL
        .transaction_date = 7470, // 2020-05-14
        .transaction_number = 0x3ffff,
        .seats_demo = 1337,
        .feature_mask = 0,
        .reserved = 0,
    };
    std.testing.expectEqualSlices(u8, IloLicenseKey.to_string(license)[0..], "3Q23VVTZ39HLB6LYNMNCC8YRN");
}

test "IloLicenseKey.format_transaction_date" {
    const license = IloLicenseKey{
        .product_id_1 = 0,
        .product_ver_1 = 0,
        .product_id_2 = 0,
        .product_ver_2 = 0,
        .product_id_3 = 0,
        .product_ver_3 = 0,
        .license_type = 0,
        .transaction_date = 7470, // 2020-05-14
        .transaction_number = 0,
        .seats_demo = 0,
        .feature_mask = 0,
        .reserved = 0,
    };
    std.testing.expectEqualSlices(u8, license.format_transaction_date()[0..], "2020-05-14");
}
