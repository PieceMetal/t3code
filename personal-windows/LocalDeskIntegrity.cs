using System;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace LocalAgentDesk
{
    public static class ProcessIntegrity
    {
        private const int IntegrityLevel = 25;
        private const int Medium = 8192;

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr data, int size, out int needed);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool SetTokenInformation(IntPtr token, int kind, IntPtr data, int size);

        [StructLayout(LayoutKind.Sequential)]
        private struct MandatoryLabel
        {
            public IntPtr Sid;
            public uint Attributes;
        }

        private static int ReadLevel(IntPtr token)
        {
            int size;
            GetTokenInformation(token, IntegrityLevel, IntPtr.Zero, 0, out size);
            if (size <= 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                if (!GetTokenInformation(token, IntegrityLevel, buffer, size, out size))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                var sid = new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value;
                return int.Parse(sid.Substring(sid.LastIndexOf('-') + 1), CultureInfo.InvariantCulture);
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        public static bool IsAtMostMedium()
        {
            using (var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query))
                return ReadLevel(identity.Token) <= Medium;
        }

        // Lower the dedicated launcher before Windows removes its administrator group.
        public static void LimitOwnProcess()
        {
            if (IsAtMostMedium()) return;
            using (var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query | TokenAccessLevels.AdjustDefault))
            {
                var sid = new SecurityIdentifier("S-1-16-8192");
                var bytes = new byte[sid.BinaryLength];
                sid.GetBinaryForm(bytes, 0);
                int header = Marshal.SizeOf(typeof(MandatoryLabel));
                int size = header + bytes.Length;
                IntPtr buffer = Marshal.AllocHGlobal(size);
                try
                {
                    IntPtr sidAddress = IntPtr.Add(buffer, header);
                    Marshal.Copy(bytes, 0, sidAddress, bytes.Length);
                    var label = new MandatoryLabel { Sid = sidAddress, Attributes = 0x20 };
                    Marshal.StructureToPtr(label, buffer, false);
                    if (!SetTokenInformation(identity.Token, IntegrityLevel, buffer, size))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    if (ReadLevel(identity.Token) > Medium)
                        throw new InvalidOperationException("Windows did not lower the launcher's integrity.");
                }
                finally { Marshal.FreeHGlobal(buffer); }
            }
        }
    }
}
