#! /usr/bin/env python

# run with
# ~/.ipython/profile_default/startup/money_value.py

from decimal import Decimal
import pytest  # pip install pytest
from re import sub


def money2float(money_str):
    return round(100 * Decimal(sub(r"[^\d.]", "", money_str))) / 100.0


def float2money(float_val):
    return "${:,.2f}".format(float_val)


def halfm(money_str):
    """Given a money string, return the string of half that money value"""
    return float2money(money2float(money_str) / 2.0)


if __name__ == "__main__":

    import pytest
    import sys

    if len(sys.argv) == 1:
        print("Running tests...")

        @pytest.mark.parametrize(
            "title, money_str, expected_float",
            [
                ["millions", "$6,150,593.22", 6150593.22],
                ["extra cents", "$6,150,593.22222", 6150593.22],
                ["round up", "$6,150,593.555", 6150593.56],
            ],
        )
        def test_money2float(title, money_str, expected_float):
            assert money2float(money_str) == expected_float, title

        @pytest.mark.parametrize(
            "title, float_value, expected_money_str",
            [
                ["millions", 6150593.2222, "$6,150,593.22"],
                ["round", 6150593.5555, "$6,150,593.56"],
            ],
        )
        def test_float2money(title, float_value, expected_money_str):
            assert float2money(float_value) == expected_money_str, title

        if len(sys.argv) > 1 and sys.argv[1] == "test":
            pytest.main([__file__])

        sys.exit(0)

    if "half" in sys.argv:
        print(halfm(sys.argv[2]))
    elif sys.argv[1] == "f2m":
        print(float2money(float(sys.argv[2])))
    elif sys.argv[1] == "m2f":
        print(money2float(sys.argv[2]))
