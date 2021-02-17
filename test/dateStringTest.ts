import {ethers} from "hardhat";
import {expect} from "chai";
import {Contract} from "ethers";

describe("DateString", () => {
  const testTimestamp = 1613496173;
  let dateTester: Contract;

  before(async () => {
    const dateTesterFactory = await ethers.getContractFactory("DateTest");
    dateTester = await dateTesterFactory.deploy();
  });

  // We test the encoding function
  it("Encodes a timestamp right", async () => {
    const encoded = await dateTester.callStatic.encodeTimestamp(testTimestamp);
    expect(encoded).to.be.eq("Tester16-FEB-21");
  });

  // We test the encoding and writing function
  it("Encodes a timestamp and writes a prefix correctly", async () => {
    const encoded = await dateTester.callStatic.encodePrefixTimestamp(
      ":YUSDC",
      testTimestamp
    );
    expect(encoded).to.be.eq("Tester:YUSDC:16-FEB-21");
  });
});
