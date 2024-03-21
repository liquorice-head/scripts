# Define the reservations with Description field
$dhcpReservations = @(
    @{IPAddress=""; MACAddress=""; ScopeId=""; Description=""},
    @{IPAddress=""; MACAddress=""; ScopeId=""; Description=""}
)

# Add each reservation
foreach ($reservation in $dhcpReservations) {
    Add-DhcpServerv4Reservation -ScopeId $reservation.ScopeId `
                                -IPAddress $reservation.IPAddress `
                                -ClientId $reservation.MACAddress `
                                -Description $reservation.Description `
                                -Name "Reservation for $($reservation.MACAddress)"
}
