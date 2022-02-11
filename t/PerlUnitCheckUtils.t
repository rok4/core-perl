# Copyright © (2011) Institut national de l'information
#                    géographique et forestière
#
# Géoportail SAV <contact.geoservices@ign.fr>
#
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
#
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use,
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info".
#
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability.
#
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or
# data to be ensured and,  more generally, to use and operate it in the
# same conditions as regards security.
#
# The fact that you are presently reading this means that you have had
#
# knowledge of the CeCILL-C license and that you accept its terms.

use strict;
use warnings;

use Test::More tests => 41;

require_ok( 'ROK4::Core::CheckUtils' );


## isStrictPositiveInt

ok(ROK4::Core::CheckUtils::isPositiveInt(+1856684), "Is a positive base 10 integer.");
ok(ROK4::Core::CheckUtils::isPositiveInt(14684), "Is a positive base 10 integer.");
ok(ROK4::Core::CheckUtils::isPositiveInt(0), "Is a positive base 10 integer.");

ok(! ROK4::Core::CheckUtils::isPositiveInt(0.5), "Is not a positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isPositiveInt(+0.5), "Is not a positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isPositiveInt(-0.5), "Is not a positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isPositiveInt("NAN"), "Is not a positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isPositiveInt(-521), "Is not a positive base 10 integer.");

## isStrictPositiveInt

ok(ROK4::Core::CheckUtils::isStrictPositiveInt(+1856684), "Is a strictly positive base 10 integer.");
ok(ROK4::Core::CheckUtils::isStrictPositiveInt(14684), "Is a strictly positive base 10 integer.");

ok(! ROK4::Core::CheckUtils::isStrictPositiveInt(0.5), "Is not a strictly positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isStrictPositiveInt(+0.5), "Is not a strictly positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isStrictPositiveInt(-0.5), "Is not a strictly positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isStrictPositiveInt("NAN"), "Is not a strictly positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isStrictPositiveInt(-521), "Is not a strictly positive base 10 integer.");
ok(! ROK4::Core::CheckUtils::isStrictPositiveInt(0), "Is not a strictly positive base 10 integer.");

## isInteger

ok(ROK4::Core::CheckUtils::isInteger(-1856164354684), "Is a base 10 integer.");
ok(ROK4::Core::CheckUtils::isInteger(+1856684), "Is a base 10 integer.");
ok(ROK4::Core::CheckUtils::isInteger(14684), "Is a base 10 integer.");
ok(ROK4::Core::CheckUtils::isInteger(0), "Is a base 10 integer.");

ok(! ROK4::Core::CheckUtils::isInteger(0.5), "Is not a base 10 integer.");
ok(! ROK4::Core::CheckUtils::isInteger(+0.5), "Is not a base 10 integer.");
ok(! ROK4::Core::CheckUtils::isInteger(-0.5), "Is not a base 10 integer.");
ok(! ROK4::Core::CheckUtils::isInteger("NAN"), "Is not a base 10 integer.");

## isNumber

ok(ROK4::Core::CheckUtils::isNumber(-1856164354684), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(+1856684), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(14684), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(0), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(0.298), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(-15.8), "Is a base 10 number.");
ok(ROK4::Core::CheckUtils::isNumber(+15.8), "Is a base 10 number.");

ok(! ROK4::Core::CheckUtils::isNumber("NAN") && ! ROK4::Core::CheckUtils::isNumber("4F2A11"), "Is not a base 10 number.");

## isBbox

ok(ROK4::Core::CheckUtils::isBbox("452.3,-89,9856,+45.369"), "Is a bbox.");

ok(! ROK4::Core::CheckUtils::isInteger("idsjfhg,oeziurh,uydcsq,iuerhg"), "Is not a bbox (not numbers)");
ok(! ROK4::Core::CheckUtils::isInteger("452.3,-89,9856"), "Is not a bbox (not 4 numbers)");
ok(! ROK4::Core::CheckUtils::isInteger("9856,-89,452.3,+45.369"), "Is not a bbox (min > max)");

## isEmpty

ok(ROK4::Core::CheckUtils::isEmpty(undef), "undef is empty.");
ok(ROK4::Core::CheckUtils::isEmpty(""), "'' is empty.");

ok(! ROK4::Core::CheckUtils::isEmpty(0), "0 is not empty.");
ok(! ROK4::Core::CheckUtils::isEmpty({}), "{} is not empty.");