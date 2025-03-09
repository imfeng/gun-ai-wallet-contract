import { expect } from "chai";
import hre, { deployments, ethers } from "hardhat";
import { AddressZero, MaxUint256 } from "@ethersproject/constants";
import { getSafe, getMock, getMultiSend } from "../utils/setup";
import {
    buildSafeTransaction,
    executeContractCallWithSigners,
    executeTx,
    executeTxWithSigners,
    MetaTransaction,
    safeSignTypedData,
} from "../../src/utils/execution";
import { AddressOne } from "../../src/utils/constants";
import { buildMultiSendSafeTx, encodeMultiSend } from "../../src/utils/multisend";

const uniswapV2Router = "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3";
const uniswapV2Factory = "0xF62c03E08ada871A0bEb309762E260a7a6a880E6";
const odosRouter = "0x0000000000000000000000000000000000000000";
describe("HexaTradingGuard", () => {
    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const signers = await ethers.getSigners();
        const [user1, user2] = signers;
        const safe = await getSafe({ owners: [user1.address] });
        const safeAddress = await safe.getAddress();
        /** Use Guard */

        const useGuard = async () => {
            const guardFactory = (await hre.ethers.getContractFactory("HexaTradingGuard")).connect(user1);
            const guard = await guardFactory.deploy(uniswapV2Router, odosRouter, safeAddress, user1.address);
            const guardAddress = await guard.getAddress();
            await executeContractCallWithSigners(safe, safe, "setGuard", [guardAddress], [user1]);
            return {
                guard,
                guardAddress,
            };
        };

        const mock = await getMock();

        const tokenFactory = await hre.ethers.getContractFactory("MockToken");
        const token1 = await tokenFactory.deploy("Token1", "TK1");
        const token2 = await tokenFactory.deploy("Token2", "TK2");

        const token1Address = await token1.getAddress();
        const token2Address = await token2.getAddress();

        (await token1.approve(uniswapV2Router, MaxUint256.toBigInt())).wait();
        (await token2.approve(uniswapV2Router, MaxUint256.toBigInt())).wait();

        const uniswapFactory = await hre.ethers.getContractAt("IUniswapV2Factory", uniswapV2Factory);
        const uniswapRouter = await hre.ethers.getContractAt("IUniswapV2Router02", uniswapV2Router);
        const pairAddress = await uniswapFactory.getPair(token1Address, token2Address);
        const pair = await hre.ethers.getContractAt("IUniswapV2Pair", pairAddress);

        const token1Amount = ethers.parseEther("100000");
        const token2Amount = ethers.parseEther("200000");

        const addLiquidityTx = await uniswapRouter.addLiquidity(
            token1Address,
            token2Address,
            token1Amount,
            token2Amount,
            0n,
            0n,
            user1.address,
            MaxUint256.toBigInt(),
        );
        const addLiquidityReceipt = await addLiquidityTx.wait();

        return {
            useGuard,
            safe,
            safeAddress,
            // guardFactory,
            // guard,
            mock,
            signers,
            token1,
            token2,
            token1Address,
            token2Address,
            pair,
            pairAddress,
            uniswapRouter,
            addLiquidityReceipt,
            multiSend: await getMultiSend(),
        };
    });

    describe("general", () => {
        it("uniswap working", async () => {
            const {
                signers: [user1],
                token1Address,
                token2Address,
                uniswapRouter,
            } = await setupTests();

            const targetToken1Amount = ethers.parseEther("1000");
            const swapTx = await uniswapRouter.swapExactTokensForTokens(
                targetToken1Amount,
                0n,
                [token1Address, token2Address],
                user1.address,
                MaxUint256.toBigInt(),
            );
            await swapTx.wait();

            // const balanceToken1 = await token1.balanceOf(user1.address);
            // const balanceToken2 = await token2.balanceOf(user1.address);
            // console.log({
            //     balanceToken1,
            //     balanceToken2,
            // });

            // const pairBalanceToken1 = await token1.balanceOf(pairAddress);
            // const pairBalanceToken2 = await token2.balanceOf(pairAddress);
            // console.log({
            //     pairBalanceToken1,
            //     pairBalanceToken2,
            // });

            // const mockAddress = await mock.getAddress();
            // const nonce = await safe.nonce();
            // const safeTx = buildSafeTransaction({ to: mockAddress, data: "0xbaddad42", nonce });

            // await executeTxWithSigners(safe.connect(user1), safeTx, [user1]);
        });

        it("safe use uniswap", async () => {
            const {
                safe,
                safeAddress,
                signers: [user1],
                token1,
                token2,
                token1Address,
                token2Address,
                uniswapRouter,
            } = await setupTests();

            const targetToken1Amount = ethers.parseEther("1000");
            await token1.mint(safeAddress, targetToken1Amount);

            /** Safe */
            const nonce = await safe.nonce();
            // safe approve token1 to uniswapRouter
            const dataApprove = token1.interface.encodeFunctionData("approve", [uniswapV2Router, targetToken1Amount]);
            const safeTxApprove = buildSafeTransaction({ to: token1Address, data: dataApprove, nonce });
            await executeTxWithSigners(safe.connect(user1), safeTxApprove, [user1]);

            // safe swapExactTokensForTokens
            const nonce2 = await safe.nonce();
            const dataSwap = uniswapRouter.interface.encodeFunctionData("swapExactTokensForTokens", [
                targetToken1Amount,
                0n,
                [token1Address, token2Address],
                safeAddress,
                MaxUint256.toBigInt(),
            ]);
            const safeTxSwap = buildSafeTransaction({ to: uniswapV2Router, data: dataSwap, nonce: nonce2 });
            await executeTxWithSigners(safe.connect(user1), safeTxSwap, [user1]);

            expect(await token1.balanceOf(safeAddress)).to.be.eq(0);
            expect(await token2.balanceOf(safeAddress)).to.be.gt(0);
        });
    });

    describe("pro", () => {
        it("guard working", async () => {
            const {
                useGuard,
                safe,
                safeAddress,
                signers: [user1],
                token1,
                token2,
                token1Address,
                token2Address,
                uniswapRouter,
            } = await setupTests();
            const { guard, guardAddress } = await useGuard();
            /** updateWhitelist */
            await executeTxWithSigners(
                safe.connect(user1),
                buildSafeTransaction({
                    to: guardAddress,
                    data: guard.interface.encodeFunctionData("updateWhitelist", [token1Address, true, MaxUint256.toBigInt()]),
                    nonce: await safe.nonce(),
                }),
                [user1],
            );
            await executeTxWithSigners(
                safe.connect(user1),
                buildSafeTransaction({
                    to: guardAddress,
                    data: guard.interface.encodeFunctionData("updateWhitelist", [token2Address, true, MaxUint256.toBigInt()]),
                    nonce: await safe.nonce(),
                }),
                [user1],
            );

            const targetToken1Amount = ethers.parseEther("1000");
            await token1.mint(safeAddress, targetToken1Amount);

            /** Safe */
            const nonce = await safe.nonce();
            // safe approve token1 to uniswapRouter
            const dataApprove = token1.interface.encodeFunctionData("approve", [uniswapV2Router, targetToken1Amount]);
            const safeTxApprove = buildSafeTransaction({ to: token1Address, data: dataApprove, nonce });
            await executeTxWithSigners(safe.connect(user1), safeTxApprove, [user1]);

            // safe swapExactTokensForTokens
            const nonce2 = await safe.nonce();
            const dataSwap = uniswapRouter.interface.encodeFunctionData("swapExactTokensForTokens", [
                targetToken1Amount,
                0n,
                [token1Address, token2Address],
                safeAddress,
                MaxUint256.toBigInt(),
            ]);
            const safeTxSwap = buildSafeTransaction({ to: uniswapV2Router, data: dataSwap, nonce: nonce2 });
            await executeTxWithSigners(safe.connect(user1), safeTxSwap, [user1]);

            expect(await token1.balanceOf(safeAddress)).to.be.eq(0);
            expect(await token2.balanceOf(safeAddress)).to.be.gt(0);
        });

        it("guard working with multiSend", async () => {
            const {
                useGuard,
                safe,
                safeAddress,
                signers: [user1],
                token1,
                token2,
                token1Address,
                token2Address,
                uniswapRouter,
                multiSend,
            } = await setupTests();
            const { guard, guardAddress } = await useGuard();

            const targetToken1Amount = ethers.parseEther("1000");
            await token1.mint(safeAddress, targetToken1Amount);

            /** updateWhitelist */
            const txsForWhitelist: MetaTransaction[] = [
                buildSafeTransaction({
                    to: guardAddress,
                    data: guard.interface.encodeFunctionData("updateWhitelist", [token1Address, true, MaxUint256.toBigInt()]),
                    nonce: 0,
                }),
                buildSafeTransaction({
                    to: guardAddress,
                    data: guard.interface.encodeFunctionData("updateWhitelist", [token2Address, true, MaxUint256.toBigInt()]),
                    nonce: 0,
                }),
            ];
            const safeTxForWhitelist = await buildMultiSendSafeTx(multiSend, txsForWhitelist, await safe.nonce());
            await executeTxWithSigners(safe.connect(user1), safeTxForWhitelist, [user1]);

            /** Safe */
            // safe approve token1 to uniswapRouter
            const dataApprove = token1.interface.encodeFunctionData("approve", [uniswapV2Router, targetToken1Amount]);
            const dataSwap = uniswapRouter.interface.encodeFunctionData("swapExactTokensForTokens", [
                targetToken1Amount,
                0n,
                [token1Address, token2Address],
                safeAddress,
                MaxUint256.toBigInt(),
            ]);

            const safeTxApprove = buildSafeTransaction({ to: token1Address, data: dataApprove, nonce: 0 });
            const safeTxSwap = buildSafeTransaction({ to: uniswapV2Router, data: dataSwap, nonce: 0 });

            const txsForSwap: MetaTransaction[] = [safeTxApprove, safeTxSwap];
            const safeTxForSwap = await buildMultiSendSafeTx(multiSend, txsForSwap, await safe.nonce());
            await executeTxWithSigners(safe.connect(user1), safeTxForSwap, [user1]);

            expect(await token1.balanceOf(safeAddress)).to.be.eq(0);
            expect(await token2.balanceOf(safeAddress)).to.be.gt(0);
        });
    });
});
